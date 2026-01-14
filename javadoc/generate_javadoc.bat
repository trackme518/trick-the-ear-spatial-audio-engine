@echo off
SETLOCAL ENABLEDELAYEDEXPANSION

REM ========================================
REM CONFIG
REM Use current user's home directory dynamically
SET USER_HOME=%USERPROFILE%

REM Path to the root of your project (relative to user home)
SET PROJECT_DIR=%USER_HOME%\Documents\GitHub\trick-the-ear-spatial-audio-engine\tea_engine

REM Path to lib folder (can contain subfolders)
SET LIB_DIR=%PROJECT_DIR%\windows-amd64\lib

REM Java source file name to search for
SET JAVA_FILE=tea_engine.java

REM Output folder for Javadoc
SET OUT=%PROJECT_DIR%\doc
REM ========================================

REM Step 1: Recursively collect all .jar files in lib folder and subfolders
SET CP=
FOR /R "%LIB_DIR%" %%f IN (*.jar) DO (
    SET CP=!CP!;%%f
)

REM Remove leading semicolon
IF "!CP:~0,1!"==";" SET CP=!CP:~1!

ECHO Classpath for Javadoc:
ECHO !CP!
ECHO.

REM Step 2: Find the Java file recursively
FOR /R "%PROJECT_DIR%" %%f IN (%JAVA_FILE%) DO (
    SET SRC=%%f
    GOTO :FOUND
)

:FOUND
IF NOT DEFINED SRC (
    ECHO ERROR: Java file %JAVA_FILE% not found in project directory.
    PAUSE
    EXIT /B 1
)

ECHO Found Java file: !SRC!
ECHO.

REM Step 3: Run Javadoc
javadoc -d "%OUT%" -classpath "!CP!" "!SRC!"

REM Step 4: Pause to see errors
PAUSE
