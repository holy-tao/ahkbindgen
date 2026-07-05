#Requires AutoHotkey v2.1-alpha.30+

/**
 * NOTE: working directory for the *interpreter* needs to be the root of the repository (where
 * ahkbuild.json lives) in order for imports from the main script to resolve. Imports within
 * test files should assume this as well. Easiest way to do this is with ahkbuild (the way the
 * GitHub action does it):
 * 
 * `ahkbuild run tests/RunTests.ahk`
 */

#Import "./YUnit/YUnit.ahk" { Yunit }
#Import "./YUnit/ResultCounter.ahk" { YunitResultCounter }
#Import "./YUnit/JUnit.ahk" { YUnitJUnit }
#Import "./YUnit/Stdout.ahk" { YUnitStdOut }

#Import "extract.test.ahk" { ExtractTests }

#Import "../src/cli" {ParseArgs, LoadLibClang}

ParseArgs(["--log-level", "trace"])
LoadLibClang()

YUnit.Use(YunitResultCounter, YUnitJUnit, YUnitStdOut).Test(
	ExtractTests
)

Exit(-YunitResultCounter.failures)