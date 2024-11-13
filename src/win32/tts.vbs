Option Explicit

Dim SAPIObject : Set SAPIObject = CreateObject("SAPI.SpVoice")
Dim VoiceTokens : Set VoiceTokens = SAPIObject.GetVoices()
Dim VoiceOutputs : Set VoiceOutputs = SAPIObject.GetAudioOutputs()
Dim StdIn : Set StdIn = CreateObject("Scripting.FileSystemObject").GetStandardStream(0)
Dim StdOut : Set StdOut = CreateObject("Scripting.FileSystemObject").GetStandardStream(1)

Dim VoiceVolume : VoiceVolume = 100
Dim VoiceRate : VoiceRate = 0.0
Dim CurrentDevice : CurrentDevice = 0

Sub ListVoices()
	Dim Voice
	For Each Voice in VoiceTokens
		StdOut.WriteLine(Voice.GetDescription)
	Next
	StdOut.WriteLine("End of voices list")
End Sub

Sub SetDevice(NewDevice)
	Dim Index : Index = 0
	Dim Device
	For Each Device in VoiceOutputs
		If (Device.GetDescription = NewDevice) Then
			CurrentDevice = Index
			
			Exit For
		End If
		
		Index = Index + 1
	Next
End Sub

Sub SpeakText(VoiceIndex, Text)
	Set SAPIObject.AudioOutput = VoiceOutputs(CurrentDevice)
	Set SAPIObject.Voice = VoiceTokens(VoiceIndex)
	SAPIObject.Volume = VoiceVolume
	SAPIObject.Rate = VoiceRate
	SAPIObject.Speak Text, 1
End Sub

Sub SetVolume(NewVolume)
	Dim NumVolume : NumVolume = CLng(NewVolume)
	If NOT(NumVolume > 100 OR NumVolume < 0) Then
		VoiceVolume = NumVolume
	Else
		VoiceVolume = 100
	End If
End Sub

Sub SetRate(NewRate)
	Dim NumRate : NumRate = CLng(NewRate)
	If NOT(NumRate > 10 OR NumRate < -10) Then
		VoiceRate = NumRate
	Else
		VoiceRate = 0.0
	End If
End Sub

Sub MainLoop()
	Dim Input
	Dim Cmd
	Dim Arguments
	Dim SplitArguments
	
	Do
		Cmd = ""
		ReDim Arguments(1)
		ReDim SplitArguments(1)
		Input = Split(StdIn.ReadLine, " ", 2, 1)
		
		If NOT(uBound(Input) = -1) Then
			Cmd = Input(0)
			If uBound(Input) = 1 Then
				Arguments = Input(1)
				SplitArguments = Split(Arguments, " ", 2, 1)
			End If
		End If
		
		If Cmd = "SpeakText" AND uBound(SplitArguments) = 1 Then
			SpeakText SplitArguments(0), SplitArguments(1)
		ElseIf Cmd = "ListVoices" Then
			ListVoices
		ElseIf Cmd = "SetVolume" AND uBound(SplitArguments) = 0 Then
			SetVolume SplitArguments(0)
		ElseIf Cmd = "SetRate" AND uBound(SplitArguments) = 0 Then
			SetRate SplitArguments(0)
		ElseIf Cmd = "SetDevice" Then
			SetDevice Arguments
		End If
	Loop While Not StdIn.AtEndOfStream
End Sub

MainLoop
