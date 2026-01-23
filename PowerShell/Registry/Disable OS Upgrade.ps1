################################################
# Author: Luis Ramirez                         #
# Updated 6-18-2020                            #
#                                              #
# Modified from Workplace Join By Kyle Pearson #
################################################
# Details...                                   #
################################################
###################################################################################
# This script checks for the existence of a Registry DWord. Then Checks the value #
# If it exists it checks the value and sets it to 1 if necessary.                 #
# If it des not exist then it creates the Dword and sets the value to 1           #
###################################################################################


# Variables for registry key, subkeys, Value Types and Values defining the settings to be toggled
$Key_1 = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
$Dword_1 = 'NoAutoUpdate'
$Value_1 = '1'

$Key_2= 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Gwx'
$Dword_2 = 'DisableGwx'
$Value_2 = '1'


#Function to create the registry key to disable windows updates.
function Set-RegistryDword {
    param(
        [string]$RegistryKey,
        [string]$RegistryDword,
        [string]$DwordValue
    )
    
    if ((Get-ItemProperty $RegistryKey -ErrorAction Ignore).PSObject.Properties.Name -contains $RegistryDword) {
        # Registry value exists - check if it has correct value
        if ((Get-ItemProperty -LiteralPath $RegistryKey).$RegistryDword -eq $DwordValue) {
            Write-Verbose "Registry value $RegistryDword is already set correctly"
            return
        }
        else {
            # Update the value
            Set-ItemProperty -LiteralPath $RegistryKey -Name $RegistryDword -Value $DwordValue -Verbose:$VerbosePreference
        }
    }
    else {
        # Registry value does not exist
        if (Test-Path -LiteralPath $RegistryKey -ErrorAction Ignore) {
            # Key exists, create the value
            New-ItemProperty -LiteralPath $RegistryKey -Name $RegistryDword -PropertyType DWORD -Value $DwordValue -Verbose:$VerbosePreference | Out-Null
        }
        else {
            # Key doesn't exist, create it and the value
            New-Item -Path $RegistryKey -Force | Out-Null
            New-ItemProperty -LiteralPath $RegistryKey -Name $RegistryDword -PropertyType DWORD -Value $DwordValue -Verbose:$VerbosePreference | Out-Null
        }
    }
    exit
    }

  
#Function to create the registry key to disable Get Windows 10 updates.  
function HKLMDisableGwx($registryKey, $registryDword, $dwordValue) {  
    if ((Get-ItemProperty $registryKey -EA Ignore).PSObject.Properties.Name -contains $registryDword) # Check if the Registry Value Exists
    {# Run this Code If it exists
        if ((Get-ItemProperty -LiteralPath $registryKey).$registryDword -eq '$dwordValue') # Test if the Dword exists and the Value is 1
            {
            exit # The Value is Correct exit the script
            }
        else
            {
            Set-ItemProperty -LiteralPath $registryKey -Name $registryDword -Value $Value_2 # -Verbose # The Value is not correct, set it to 1
            }
    }
    else # Run this Code if it does not exist
    {
    if (Test-Path -LiteralPath $registryKey -EA Ignore) #Tests if the registry Key exists
        {
        New-ItemProperty -LiteralPath $registryKey -Name $registryDword -PropertyType DWORD -Value $Value_2 # -Verbose # Create the Dword and set the value as 1
        exit
        }
    else
    {
    New-Item -Path $registryKey # Create the WindowsUpdate Key
    New-ItemProperty -LiteralPath $registryKey -Name $registryDword -PropertyType DWORD -Value $Value_2 # -Verbose # Create the Dword and set the value as 1
    }
    exit
    }
  }   
  
HKLMNoAutoUpdate $Key_1 $Dword_1 $Value_1
HKLMDisableGwx $Key_2 $Dword_2 $Value_2