unit noe2;

{$mode objfpc}{$H+}
{$modeswitch advancedRecords}

interface

uses
  Classes, SysUtils, multiarray, numerik, fgl;

type

  TTensor = class
    Data: TMultiArray;
    FBackwardFunc: Pointer;

    Deps: array of TTensor;
  private

    FGrad: TMultiArray;
    FRequiresGrad: boolean;
    function GetShape: TLongVector;
    procedure AddDependencies(ADeps: array of TTensor);
    procedure SetRequiresGrad(val: boolean);
  public
    procedure Backward(G: TMultiArray);
    destructor Destroy; override;
    property Grad: TMultiArray read FGrad write FGrad;
    property RequiresGrad: boolean read FRequiresGrad write SetRequiresGrad;
    property Shape: TLongVector read GetShape;
  end;

  TBackwardFunc = procedure(var arr: array of TTensor; G: TMultiArray);
  TTensorList = specialize TFPGObjectList<TTensor>;

procedure PrintTensor(T: TTensor);

function CreateTensor(Data: TMultiArray; RequiresGrad: boolean=False): TTensor;

function Add(A, B: TTensor): TTensor; overload;

operator :=(A: TMultiArray) B: TTensor;


var
  NoeGlobalTensorList: TTensorList;

implementation

procedure TTensor.AddDependencies(ADeps: array of TTensor);
var
  i: integer;
begin
  SetLength(Deps, Length(ADeps));
  for i := 0 to High(ADeps) do
  begin
    Self.RequiresGrad := Self.RequiresGrad or ADeps[i].RequiresGrad;
    if ADeps[i].RequiresGrad then
      Deps[i] := ADeps[i];
  end;
end;

procedure TTensor.SetRequiresGrad(val: boolean);
begin
  self.FRequiresGrad := val;
  if val then
    self.Grad := Zeros(Self.Data.Shape)
  else
    self.Grad := AllocateMultiArray(0);
end;

procedure TTensor.Backward(G: TMultiArray);
var
  Dep: TTensor;
begin
  self.Grad := G;
  TBackwardFunc(Self.FBackwardFunc)(Self.Deps, Self.Grad);
  for Dep in Self.Deps do
    if Assigned(Dep.FBackwardFunc) then
      TBackwardFunc(Dep.FBackwardFunc)(Dep.Deps, Dep.Grad);
end;

destructor TTensor.Destroy;
begin
  self.Deps := nil;
end;

procedure PrintTensor(T: TTensor);
begin
  PrintMultiArray(T.Data);
end;

function CreateTensor(Data: TMultiArray; RequiresGrad: boolean=False): TTensor;
begin
  Result := TTensor.Create;
  Result.RequiresGrad := RequiresGrad;
  Result.Data := Data;
  Result.FBackwardFunc := nil;
  NoeGlobalTensorList.Add(Result);
end;

function ReduceGradToShape(Grad: TMultiArray; Shape: TLongVector): TMultiArray;
var
  i, NDimsAdded: integer;
begin
  NDimsAdded := Grad.NDims - Length(Shape);
  for i := 0 to NDimsAdded - 1 do
    Grad := Sum(Grad, 0);

  for i := 0 to High(Shape) do
    if Shape[i] = 1 then
      Grad := Sum(Grad, i, True);
  Result := Grad;
end;

procedure AddBackward(var Deps: array of TTensor; G: TMultiArray);
begin
  if Deps[0].RequiresGrad then
    Deps[0].Grad := Deps[0].Grad + ReduceGradToShape(G, Deps[0].Shape);
  if Deps[1].RequiresGrad then
    Deps[1].Grad := Deps[1].Grad + ReduceGradToShape(G, Deps[1].Shape);
end;

function Add(A, B: TTensor): TTensor;
begin
  Result := A.Data + B.Data;
  Result.AddDependencies([A, B]);
  Result.FBackwardFunc := @AddBackward;
end;

operator +(A, B: TTensor)C: TTensor;
begin
  C := Add(A, B);
end;

function TTensor.GetShape: TLongVector;
begin
  Exit(Self.Data.Shape);
end;

operator :=(A: TMultiArray) B: TTensor;
begin
  B := CreateTensor(A);
end;

initialization

  NoeGlobalTensorList := TTensorList.Create;

finalization
  NoeGlobalTensorList.Free;

end.
