rem | Version 10.1.1
rem | Copyright 2012 Esri
rem |
rem | Licensed under the Apache License, Version 2.0 (the "License");
rem | you may not use this file except in compliance with the License.
rem | You may obtain a copy of the License at
rem |
rem |    http://www.apache.org/licenses/LICENSE-2.0
rem |
rem | Unless required by applicable law or agreed to in writing, software
rem | distributed under the License is distributed on an "AS IS" BASIS,
rem | WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
rem | See the License for the specific language governing permissions and
rem | limitations under the License.
set WORKSPACE=%cd%
"C:\Program Files (x86)\Adobe\Adobe Flash Builder 4.6\FlashBuilderC.exe" ^
    --launcher.suppressErrors ^
    -noSplash ^
    -application org.eclipse.ant.core.antRunner ^
    -data "%WORKSPACE%" ^
    -file "%cd%\flexbuild.xml"
