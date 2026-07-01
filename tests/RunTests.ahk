#Requires AutoHotkey v2.1-alpha.30+

#Import "./YUnit/YUnit.ahk" { Yunit }
#Import "./YUnit/ResultCounter.ahk" { YunitResultCounter }
#Import "./YUnit/JUnit.ahk" { YUnitJUnit }
#Import "./YUnit/Stdout.ahk" { YUnitStdOut }

YUnit.Use(YunitResultCounter, YUnitJUnit, YUnitStdOut).Test(
	; Add test classes here
)

Exit(-YunitResultCounter.failures)