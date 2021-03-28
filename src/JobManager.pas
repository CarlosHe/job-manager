unit JobManager;

interface

uses
  System.Classes, System.DateUtils, System.SysUtils, System.SyncObjs,
  System.Generics.Collections, System.Threading;

type

  TJobItem = class
  private
    Interval: Integer;
    Timeout: TNotifyEvent;
  public
    LastTimeout: TDateTime;
    constructor Create(AInterval: Integer; ATimeout: TNotifyEvent);
    function NeedExecute(ANow: TDateTime): Boolean;
    procedure ExecuteJob(Sender: TObject);
  end;

  TJobManager = class(TThread)
  private
    FCriticalSection: TCriticalSection;
    FEvent: TEvent;
    FJobList: TObjectList<TJobItem>;
    class var FJobManager: TJobManager;
    { private declarations }
  protected
    { protected declarations }
    class function GetDefaultJobManager: TJobManager;
  public
    { public declarations }
    class function DefaultJobManager: TJobManager;
    class destructor UnInitialize;
    procedure AfterConstruction; override;
    procedure BeforeDestruction; override;
    procedure Execute; override;
    function AddJob(AJob: TJobItem): Integer;
    function RemoveJob(AJob: TJobItem): Integer;
  end;

implementation

{ TJobManager }

function TJobManager.AddJob(AJob: TJobItem): Integer;
begin
  FCriticalSection.Enter;
  try
    Result := FJobList.Add(AJob);
    FJobList.TrimExcess;
  finally
    FCriticalSection.Leave;
  end;
end;

procedure TJobManager.AfterConstruction;
begin
  inherited;
  FCriticalSection := TCriticalSection.Create;
  FEvent := TEvent.Create;
  FJobList := TObjectList<TJobItem>.Create;
end;

procedure TJobManager.BeforeDestruction;
begin
  inherited;
  FJobList.Free;
  FEvent.Free;
  FCriticalSection.Free;
end;

class function TJobManager.DefaultJobManager: TJobManager;
begin
  Result := GetDefaultJobManager;
end;

procedure TJobManager.Execute;
var
  LCurrentDateTime: TDateTime;
  I: Int64;
begin
  inherited;
  while not Terminated do
  begin
    FEvent.WaitFor(100);
    if Terminated then
      Break;
    FCriticalSection.Enter;
    try
      LCurrentDateTime := Now();
      TParallel.&For(0, FJobList.Count - 1,
        procedure(I: Int64)
        begin
          if (FJobList.Items[I].NeedExecute(LCurrentDateTime)) then
            FJobList.Items[I].ExecuteJob(Self);
        end);
    finally
      FCriticalSection.Leave;
    end;
  end;
end;

class function TJobManager.GetDefaultJobManager: TJobManager;
begin
  if not Assigned(FJobManager) then
  begin
    FJobManager := TJobManager.Create(True);
    FJobManager.FreeOnTerminate := True;
{$IFDEF MSWINDOWS}
    FJobManager.Priority := TThreadPriority.tpLowest;
{$ENDIF}
    FJobManager.Start;
  end;
  Result := FJobManager;
end;

function TJobManager.RemoveJob(AJob: TJobItem): Integer;
begin
  FCriticalSection.Enter;
  try
    FJobList.Remove(AJob);
    FJobList.TrimExcess;
  finally
    FCriticalSection.Leave;
  end;
end;

class destructor TJobManager.UnInitialize;
begin
  if Assigned(FJobManager) then
    FJobManager.Terminate;
  FJobManager.FEvent.SetEvent;
end;

{ TJobItem }

constructor TJobItem.Create(AInterval: Integer; ATimeout: TNotifyEvent);
begin
  Interval := AInterval;
  Timeout := ATimeout;
  LastTimeout := Now();
end;

procedure TJobItem.ExecuteJob(Sender: TObject);
var
  LTimeout: TNotifyEvent;
  LInstance: TObject;
begin
  LastTimeout := Now();
  LTimeout := Timeout;
  LInstance := Sender;
  try
    if Assigned(LTimeout) then
      TThread.Queue(nil,
        procedure
        begin
          LTimeout(LInstance);
        end);
  except
  end;
end;

function TJobItem.NeedExecute(ANow: TDateTime): Boolean;
begin
  Result := SecondsBetween(ANow, LastTimeout) >= Interval
end;

end.
