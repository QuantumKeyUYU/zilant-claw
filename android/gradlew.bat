@ECHO OFF
SET DIR=%~dp0
SET WRAPPER_JAR=%DIR%\gradle\wrapper\gradle-wrapper.jar
IF NOT EXIST "%WRAPPER_JAR%" (
  ECHO Gradle wrapper not found.
  EXIT /B 1
)
java -Xmx64m -classpath "%WRAPPER_JAR%" org.gradle.wrapper.GradleWrapperMain %*
