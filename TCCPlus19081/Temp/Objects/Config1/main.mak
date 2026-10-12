SHELL = cmd.exe
CYGWIN=nontsec
export PATH := C:\Program Files (x86)\VMware\VMware Workstation\bin\;C:\RoboDK\Python37\Scripts\;C:\RoboDK\Python37\;C:\Program Files\Python313\Scripts\;C:\Program Files\Python313\;C:\Program Files (x86)\Common Files\Oracle\Java\java8path;C:\Windows\system32;C:\Windows;C:\Windows\System32\Wbem;C:\Windows\System32\WindowsPowerShell\v1.0\;C:\Program Files\MATLAB\R2024b\runtime\win64;C:\Program Files\MATLAB\R2024b\bin;C:\Program Files\Microsoft VS Code\bin;C:\Program Files\nodejs\;C:\Program Files\dotnet\;C:\Program Files (x86)\Common Files\Rockwell\;C:\Program Files\Common Files\Rockwell\FTLD\;C:\Program Files (x86)\Common Files\Rockwell\FTLD\;C:\Program Files (x86)\Rockwell Software\RSCommon;C:\Program Files (x86)\Common Files\Rockwell;C:\Program Files (x86)\Common Files\Rockwell\FactoryTalk Linx\;C:\Program Files (x86)\Rockwell Software\Logix Designer Tools\Logix Designer Compare Tool\;C:\Users\supervisorio\AppData\Local\Microsoft\WindowsApps;C:\Users\supervisorio\AppData\Local\Programs\Git\cmd;C:\Users\supervisorio\AppData\Local\Microsoft\WindowsApps;C:\Users\supervisorio\AppData\Local\Programs\Git\cmd
export AS_BUILD_MODE := BuildAndTransfer
export AS_VERSION := 4.1.14.40 SP
export AS_COMPANY_NAME :=  
export AS_USER_NAME := supervisorio
export AS_PATH := C:/BrAutomation/AS41
export AS_BIN_PATH := C:/BrAutomation/AS41/Bin-en
export AS_PROJECT_PATH := C:/Users/supervisorio/Downloads/TCCPlus2/TCCPlus1908
export AS_PROJECT_NAME := TCCPlus1908
export AS_SYSTEM_PATH := C:/BrAutomation/AS/System
export AS_VC_PATH := C:/BrAutomation/AS41/AS/VC
export AS_TEMP_PATH := C:/Users/supervisorio/Downloads/TCCPlus2/TCCPlus1908/Temp
export AS_CONFIGURATION := Config1
export AS_BINARIES_PATH := C:/Users/supervisorio/Downloads/TCCPlus2/TCCPlus1908/Binaries
export AS_GNU_INST_PATH := C:/BrAutomation/AS41/AS/GnuInst/V4.1.2
export AS_GNU_BIN_PATH := $(AS_GNU_INST_PATH)/bin
export AS_GNU_INST_PATH_SUB_MAKE := C:/BrAutomation/AS41/AS/GnuInst/V4.1.2
export AS_GNU_BIN_PATH_SUB_MAKE := $(AS_GNU_INST_PATH_SUB_MAKE)/bin
export AS_INSTALL_PATH := C:/BrAutomation/AS41
export WIN32_AS_PATH := C:\\BrAutomation\\AS41
export WIN32_AS_BIN_PATH := C:\\BrAutomation\\AS41\\Bin-en
export WIN32_AS_PROJECT_PATH := C:\\Users\\supervisorio\\Downloads\\TCCPlus2\\TCCPlus1908
export WIN32_AS_SYSTEM_PATH := C:\\BrAutomation\\AS\\System
export WIN32_AS_VC_PATH := C:\\BrAutomation\\AS41\\AS\\VC
export WIN32_AS_TEMP_PATH := C:\\Users\\supervisorio\\Downloads\\TCCPlus2\\TCCPlus1908\\Temp
export WIN32_AS_BINARIES_PATH := C:\\Users\\supervisorio\\Downloads\\TCCPlus2\\TCCPlus1908\\Binaries
export WIN32_AS_GNU_INST_PATH := C:\\BrAutomation\\AS41\\AS\\GnuInst\\V4.1.2
export WIN32_AS_GNU_BIN_PATH := $(WIN32_AS_GNU_INST_PATH)\\bin
export WIN32_AS_INSTALL_PATH := C:\\BrAutomation\\AS41

.suffixes:

ProjectMakeFile:

	@"$(AS_BIN_PATH)/BR.AS.AnalyseProject.exe" "$(AS_PROJECT_PATH)/TCCPlus1908.apj" -t "$(AS_TEMP_PATH)" -c "$(AS_CONFIGURATION)" -o "$(AS_BINARIES_PATH)"   -sfas -buildMode "BuildAndTransfer" 

	@$(AS_GNU_BIN_PATH)/mingw32-make.exe -r -f 'C:/Users/supervisorio/Downloads/TCCPlus2/TCCPlus1908/Temp/Objects/$(AS_CONFIGURATION)/X20CP1583/#cpu.mak' -k 

