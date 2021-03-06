{==============================================================================|
| Project : Delphree - Synapse                                   | 002.001.004 |
|==============================================================================|
| Content: SMTP client                                                         |
|==============================================================================|
| The contents of this file are Subject to the Mozilla Public License Ver. 1.1 |
| (the "License"); you may not use this file except in compliance with the     |
| License. You may obtain a Copy of the License at http://www.mozilla.org/MPL/ |
|                                                                              |
| Software distributed under the License is distributed on an "AS IS" basis,   |
| WITHOUT WARRANTY OF ANY KIND, either express or implied. See the License for |
| the specific language governing rights and limitations under the License.    |
|==============================================================================|
| The Original Code is Synapse Delphi Library.                                 |
|==============================================================================|
| The Initial Developer of the Original Code is Lukas Gebauer (Czech Republic).|
| Portions created by Lukas Gebauer are Copyright (c) 1999,2000,2001.          |
| All Rights Reserved.                                                         |
|==============================================================================|
| Contributor(s):                                                              |
|==============================================================================|
| History: see HISTORY.HTM from distribution package                           |
|          (Found at URL: http://www.ararat.cz/synapse/)                       |
|==============================================================================}

{$WEAKPACKAGEUNIT ON}

unit SMTPsend;

interface

uses
  KOL,
  blcksock, SynaUtil, SynaCode;

const
  cSmtpProtocol = 'smtp';

type
  PSMTPSend = ^TSMTPSend;
  TSMTPSend = object(TObj)
  private
    FSock: PTCPBlockSocket;
    FTimeout: Integer;
    FSMTPHost: string;
    FSMTPPort: string;
    FResultCode: Integer;
    FResultString: string;
    FFullResult: PStrList;
    FESMTPcap: PStrList;
    FESMTP: Boolean;
    FUsername: string;
    FPassword: string;
    FAuthDone: Boolean;
    FESMTPSize: Boolean;
    FMaxSize: Integer;
    FEnhCode1: Integer;
    FEnhCode2: Integer;
    FEnhCode3: Integer;
    FSystemName: string;
    procedure EnhancedCode(const Value: string);
    function ReadResult: Integer;
    function AuthLogin: Boolean;
    function AuthCram: Boolean;
    function Helo: Boolean;
    function Ehlo: Boolean;
    function Connect: Boolean;
  public
    destructor Destroy; virtual;
    function Login: Boolean;
    procedure Logout;
    function Reset: Boolean;
    function NoOp: Boolean;
    function MailFrom(const Value: string; Size: Integer): Boolean;
    function MailTo(const Value: string): Boolean;
    function MailData(Value: PStrList): Boolean;
    function Etrn(const Value: string): Boolean;
    function Verify(const Value: string): Boolean;
    function EnhCodeString: string;
    function FindCap(const Value: string): string;
    property Timeout: Integer read FTimeout Write FTimeout;
    property SMTPHost: string read FSMTPHost Write FSMTPHost;
    property SMTPPort: string read FSMTPPort Write FSMTPPort;
    property ResultCode: Integer read FResultCode;
    property ResultString: string read FResultString;
    property FullResult: PStrList read FFullResult;
    property ESMTPcap: PStrList read FESMTPcap;
    property ESMTP: Boolean read FESMTP;
    property Username: string read FUsername Write FUsername;
    property Password: string read FPassword Write FPassword;
    property AuthDone: Boolean read FAuthDone;
    property ESMTPSize: Boolean read FESMTPSize;
    property MaxSize: Integer read FMaxSize;
    property EnhCode1: Integer read FEnhCode1;
    property EnhCode2: Integer read FEnhCode2;
    property EnhCode3: Integer read FEnhCode3;
    property SystemName: string read FSystemName Write FSystemName;
    property Sock: PTCPBlockSocket read FSock;
  end;

function SendToRaw(const MailFrom, MailTo, SMTPHost: string;
  MailData: PStrList; const Username, Password: string): Boolean;
function SendTo(const MailFrom, MailTo, Subject, SMTPHost: string;
  MailData: PStrList): Boolean;
function SendToEx(const MailFrom, MailTo, Subject, SMTPHost: string;
  MailData: PStrList; const Username, Password: string): Boolean;

function NewSMTPSend : PSMTPSend;  

implementation

const
  CRLF = #13#10;

function NewSMTPSend : PSMTPSend;
begin
  New(Result,Create);
  Result.FFullResult := NewStrList;//TStringList.Create;
  Result.FESMTPcap := NewStrList;//TStringList.Create;
  Result.FSock := NewTCPBlockSocket;//.Create;
  Result.FSock.CreateSocket;
  Result.FTimeout := 300000;
  Result.FSMTPhost := cLocalhost;
  Result.FSMTPPort := cSmtpProtocol;
  Result.FUsername := '';
  Result.FPassword := '';
  Result.FSystemName := Result.FSock.LocalName;
end;

destructor TSMTPSend.Destroy;
begin
  FSock.Free;
  FESMTPcap.Free;
  FFullResult.Free;
  inherited Destroy;
end;

procedure TSMTPSend.EnhancedCode(const Value: string);
var
  s, t: string;
  e1, e2, e3: Integer;
begin
  FEnhCode1 := 0;
  FEnhCode2 := 0;
  FEnhCode3 := 0;
  s := Copy(Value, 5, Length(Value) - 4);
  t := SeparateLeft(s, '.');
  s := SeparateRight(s, '.');
  if t = '' then
    Exit;
  if Length(t) > 1 then
    Exit;
  e1 := StrToIntDef(t, 0);
  if e1 = 0 then
    Exit;
  t := SeparateLeft(s, '.');
  s := SeparateRight(s, '.');
  if t = '' then
    Exit;
  if Length(t) > 3 then
    Exit;
  e2 := StrToIntDef(t, 0);
  t := SeparateLeft(s, ' ');
  if t = '' then
    Exit;
  if Length(t) > 3 then
    Exit;
  e3 := StrToIntDef(t, 0);
  FEnhCode1 := e1;
  FEnhCode2 := e2;
  FEnhCode3 := e3;
end;

function TSMTPSend.ReadResult: Integer;
var
  s: string;
begin
  Result := 0;
  FFullResult.Clear;
  repeat
    s := FSock.RecvString(FTimeout);
    FResultString := s;
    FFullResult.Add(s);
    if FSock.LastError <> 0 then
      Break;
  until Pos('-', s) <> 4;
  s := FFullResult.Items[0];
  if Length(s) >= 3 then
    Result := StrToIntDef(Copy(s, 1, 3), 0);
  FResultCode := Result;
  EnhancedCode(s);
end;

function TSMTPSend.AuthLogin: Boolean;
begin
  Result := False;
  FSock.SendString('AUTH LOGIN' + CRLF);
  if ReadResult <> 334 then
    Exit;
  FSock.SendString(EncodeBase64(FUsername) + CRLF);
  if ReadResult <> 334 then
    Exit;
  FSock.SendString(EncodeBase64(FPassword) + CRLF);
  Result := ReadResult = 235;
end;

function TSMTPSend.AuthCram: Boolean;
var
  s: string;
begin
  Result := False;
  FSock.SendString('AUTH CRAM-MD5' + CRLF);
  if ReadResult <> 334 then
    Exit;
  s := Copy(FResultString, 5, Length(FResultString) - 4);
  s := DecodeBase64(s);
  s := HMAC_MD5(s, FPassword);
  s := FUsername + ' ' + StrToHex(s);
  FSock.SendString(EncodeBase64(s) + CRLF);
  Result := ReadResult = 235;
end;

function TSMTPSend.Connect: Boolean;
begin
  FSock.CloseSocket;
  FSock.CreateSocket;
  FSock.Connect(FSMTPHost, FSMTPPort);
  Result := FSock.LastError = 0;
end;

function TSMTPSend.Helo: Boolean;
var
  x: Integer;
begin
  FSock.SendString('HELO ' + FSystemName + CRLF);
  x := ReadResult;
  Result := (x >= 250) and (x <= 259);
end;

function TSMTPSend.Ehlo: Boolean;
var
  x: Integer;
begin
  FSock.SendString('EHLO ' + FSystemName + CRLF);
  x := ReadResult;
  Result := (x >= 250) and (x <= 259);
end;

function TSMTPSend.Login: Boolean;
var
  n: Integer;
  auths: string;
  s: string;
begin
  Result := False;
  FESMTP := True;
  FAuthDone := False;
  FESMTPcap.clear;
  FESMTPSize := False;
  FMaxSize := 0;
  if not Connect then
    Exit;
  if ReadResult <> 220 then
    Exit;
  if not Ehlo then
  begin
    FESMTP := False;
    if not Helo then
      Exit;
  end;
  Result := True;
  if FESMTP then
  begin
    for n := 1 to FFullResult.Count - 1 do
      FESMTPcap.Add(Copy(FFullResult.Items[n], 5, Length(FFullResult.Items[n]) - 4));
    if not ((FUsername = '') and (FPassword = '')) then
    begin
      s := FindCap('AUTH ');
      if s = '' then
        s := FindCap('AUTH=');
      auths := UpperCase(s);
      if s <> '' then
      begin
        if Pos('CRAM-MD5', auths) > 0 then
          FAuthDone := AuthCram;
        if (Pos('LOGIN', auths) > 0) and (not FauthDone) then
          FAuthDone := AuthLogin;
      end;
      if FAuthDone then
        Ehlo;
    end;
    s := FindCap('SIZE');
    if s <> '' then
    begin
      FESMTPsize := True;
      FMaxSize := StrToIntDef(Copy(s, 6, Length(s) - 5), 0);
    end;
  end;
end;

procedure TSMTPSend.Logout;
begin
  FSock.SendString('QUIT' + CRLF);
  ReadResult;
  FSock.CloseSocket;
end;

function TSMTPSend.Reset: Boolean;
begin
  FSock.SendString('RSET' + CRLF);
  Result := ReadResult = 250;
end;

function TSMTPSend.NoOp: Boolean;
begin
  FSock.SendString('NOOP' + CRLF);
  Result := ReadResult = 250;
end;

function TSMTPSend.MailFrom(const Value: string; Size: Integer): Boolean;
var
  s: string;
begin
  s := 'MAIL FROM:<' + Value + '>';
  if FESMTPsize and (Size > 0) then
    s := s + ' SIZE=' + Int2Str(Size);
  FSock.SendString(s + CRLF);
  Result := ReadResult = 250;
end;

function TSMTPSend.MailTo(const Value: string): Boolean;
begin
  FSock.SendString('RCPT TO:<' + Value + '>' + CRLF);
  Result := ReadResult = 250;
end;

function TSMTPSend.MailData(Value: PStrList): Boolean;
var
  n,l: Integer;
  s: string;
begin
  Result := False;
  l := Value.Count;
  FSock.SendString('DATA' + CRLF);
  if ReadResult <> 354 then
    Exit;
  for n := 0 to l - 1 do
  begin
    s := Value.Items[n];
    if Length(s) >= 1 then
      if s[1] = '.' then
        s := '.' + s;
    FSock.SendString(s + CRLF);
  end;
  FSock.SendString('.' + CRLF);
  Result := ReadResult = 250;
end;

function TSMTPSend.Etrn(const Value: string): Boolean;
var
  x: Integer;
begin
  FSock.SendString('ETRN ' + Value + CRLF);
  x := ReadResult;
  Result := (x >= 250) and (x <= 259);
end;

function TSMTPSend.Verify(const Value: string): Boolean;
var
  x: Integer;
begin
  FSock.SendString('VRFY ' + Value + CRLF);
  x := ReadResult;
  Result := (x >= 250) and (x <= 259);
end;

function TSMTPSend.EnhCodeString: string;
var
  s, t: string;
begin
  s := Int2Str(FEnhCode2) + '.' + Int2Str(FEnhCode3);
  t := '';
  if s = '0.0' then t := 'Other undefined Status';
  if s = '1.0' then t := 'Other address status';
  if s = '1.1' then t := 'Bad destination mailbox address';
  if s = '1.2' then t := 'Bad destination system address';
  if s = '1.3' then t := 'Bad destination mailbox address syntax';
  if s = '1.4' then t := 'Destination mailbox address ambiguous';
  if s = '1.5' then t := 'Destination mailbox address valid';
  if s = '1.6' then t := 'Mailbox has moved';
  if s = '1.7' then t := 'Bad sender''s mailbox address syntax';
  if s = '1.8' then t := 'Bad sender''s system address';
  if s = '2.0' then t := 'Other or undefined mailbox status';
  if s = '2.1' then t := 'Mailbox disabled, not accepting messages';
  if s = '2.2' then t := 'Mailbox full';
  if s = '2.3' then t := 'Message Length exceeds administrative limit';
  if s = '2.4' then t := 'Mailing list expansion problem';
  if s = '3.0' then t := 'Other or undefined mail system status';
  if s = '3.1' then t := 'Mail system full';
  if s = '3.2' then t := 'System not accepting network messages';
  if s = '3.3' then t := 'System not capable of selected features';
  if s = '3.4' then t := 'Message too big for system';
  if s = '3.5' then t := 'System incorrectly configured';
  if s = '4.0' then t := 'Other or undefined network or routing status';
  if s = '4.1' then t := 'No answer from host';
  if s = '4.2' then t := 'Bad connection';
  if s = '4.3' then t := 'Routing server failure';
  if s = '4.4' then t := 'Unable to route';
  if s = '4.5' then t := 'Network congestion';
  if s = '4.6' then t := 'Routing loop detected';
  if s = '4.7' then t := 'Delivery time expired';
  if s = '5.0' then t := 'Other or undefined protocol status';
  if s = '5.1' then t := 'Invalid command';
  if s = '5.2' then t := 'Syntax error';
  if s = '5.3' then t := 'Too many recipients';
  if s = '5.4' then t := 'Invalid command arguments';
  if s = '5.5' then t := 'Wrong protocol version';
  if s = '6.0' then t := 'Other or undefined media error';
  if s = '6.1' then t := 'Media not supported';
  if s = '6.2' then t := 'Conversion required and prohibited';
  if s = '6.3' then t := 'Conversion required but not supported';
  if s = '6.4' then t := 'Conversion with loss performed';
  if s = '6.5' then t := 'Conversion failed';
  if s = '7.0' then t := 'Other or undefined security status';
  if s = '7.1' then t := 'Delivery not authorized, message refused';
  if s = '7.2' then t := 'Mailing list expansion prohibited';
  if s = '7.3' then t := 'Security conversion required but not possible';
  if s = '7.4' then t := 'Security features not supported';
  if s = '7.5' then t := 'Cryptographic failure';
  if s = '7.6' then t := 'Cryptographic algorithm not supported';
  if s = '7.7' then t := 'Message integrity failure';
  s := '???-';
  if FEnhCode1 = 2 then s := 'Success-';
  if FEnhCode1 = 4 then s := 'Persistent Transient Failure-';
  if FEnhCode1 = 5 then s := 'Permanent Failure-';
  Result := s + t;
end;

function TSMTPSend.FindCap(const Value: string): string;
var
  n: Integer;
  s: string;
begin
  s := UpperCase(Value);
  Result := '';
  for n := 0 to FESMTPcap.Count - 1 do
    if Pos(s, UpperCase(FESMTPcap.Items[n])) = 1 then
    begin
      Result := FESMTPcap.Items[n];
      Break;
    end;
end;

{==============================================================================}

function SendToRaw(const MailFrom, MailTo, SMTPHost: string;
  MailData: PStrList; const Username, Password: string): Boolean;
var
  SMTP: PSMTPSend;
begin
  Result := False;
  SMTP := NewSMTPSend;
  try
    SMTP.SMTPHost := SMTPHost;
    SMTP.Username := Username;
    SMTP.Password := Password;
    if SMTP.Login then
    begin
      if SMTP.MailFrom(MailFrom, Length(MailData.Text)) then
        if SMTP.MailTo(MailTo) then
          if SMTP.MailData(MailData) then
            Result := True;
      SMTP.Logout;
    end;
  finally
    SMTP.Free;
  end;
end;

function SendToEx(const MailFrom, MailTo, Subject, SMTPHost: string;
  MailData: PStrList; const Username, Password: string): Boolean;
var
  t: PStrList;
begin
  t := NewStrList;
  try
    t.Assign(MailData);
    t.Insert(0, '');
    t.Insert(0, 'x-mailer: Synapse - Delphi TCP/IP library by Lukas Gebauer');
    t.Insert(0, 'subject: ' + Subject);
    t.Insert(0, 'date: ' + Rfc822DateTime(now));
    t.Insert(0, 'to: ' + MailTo);
    t.Insert(0, 'from: ' + MailFrom);
    Result := SendToRaw(MailFrom, MailTo, SMTPHost, t, Username, Password);
  finally
    t.Free;
  end;
end;

function SendTo(const MailFrom, MailTo, Subject, SMTPHost: string;
  MailData: PStrList): Boolean;
begin
  Result := SendToEx(MailFrom, MailTo, Subject, SMTPHost, MailData, '', '');
end;

end.
