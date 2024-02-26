<#
.SYNOPSIS
Compare-CollectionsLinq - This script compares two like objects using linq. it is generally quicker than using compare-collectionsSQL

.DESCRIPTION
Detailed description of the script and what it is for.

.EXAMPLE
Compare-CollectionsLinq.ps1 -param1 "Value"
Give an example of common usage.  Repeat EXAMPLE as desired

.PARAMETER CollectionA
Required.  A Collection of objects to compare.  This is the first collection to compare.

.PARAMETER CollectionB
Required.  A Collection of objects to compare.  This is the second collection to compare.

.PARAMETER Properties
Required.  An array of properties in the objects to compare.

.PARAMETER CaseSensitive
Optional.  A switch to indicate if the comparison should be case sensitive.  Default is false.

.NOTES
Author:           @markdomansky
Creation Date:    2022-02-22 10:18
History:
    2022-02-22 10:18, 1.0, @markdomansky, Initial Creation


This template is CC0/1.0 Public Domain and can be found at github.com/markdomansky/PSScriptTemplate
#NOTE This comment block MUST come before everything else (except a function definition).
#>
##requires -version 4.0 #3, #6
#remove extra # to enable a requires
##requires -runasadministrator
##requires -modules <module-name>,<module-name> #repeat as desired, replace <module-name> with @{ModuleName="X";ModuleVersion="1.0.0.0"} if you want specific versions
##requires -shellid <shellid>

[CmdletBinding(SupportsShouldProcess = $True, ConfirmImpact = 'Medium')]
#SupportsShouldProcess=$true - enabled support for -Whatif and -Confirm.  PSSA will warn if specified but not $cmdlet.shouldprocess exists
#ConfirmImpact='Medium' (Low, Medium (default), High) will prompt for action where $pscmdlet.shouldprocess is called and ConfirmImpact -ge $ConfirmPreference (default=High)
#$pscmdlet.ShouldProcess("target",["action"]), generally part of an if statement.  When called, this checks both -whatif and the confirmimpact vs $confirmpreference.
#Whatif overrides confirmimpact, if confirmimpact -ge $confirmpreference, a prompt is generated.  -Confirm:$false to force no prompt, -confirm to force a prompt regardless of confirmpreference
#DefaultParameterSetName="X" whatever parameterset used below
#HelpUri="Uri" used to store help documentation elsewhere: http://msdn.microsoft.com/en-us/library/dd878343(v=vs.85).aspx
#SupportsPaging=$true - adds First,Skip, IncludeTotalCount parameters automatically PSv3 req'd
#PositionalBinding=$false - default true, allows parameters by position, when false, all parameters must be defined by name (-computername "X")

#NOTE whatif, confirm, verbose, and debug are all passed through to sub-cmdlets/scripts called within the script.

param
(
    #Parameter Templates are at the bottom of the script

    [Parameter(Position = 0, Mandatory)]
    [Alias('A', 'ColA', 'Collection1')]
    [Object[]]$CollectionA,

    [Parameter(Position = 1, Mandatory)]
    [Alias('B', 'ColB', 'Collection2')]
    [Object[]]$CollectionB,

    [Parameter(Position = 2, Mandatory)]
    [Alias('Properties')]
    [ValidateNotNullOrEmpty()]
    [String[]]$Property,

    [Parameter()]
    [Switch]$CaseSensitive

) #/param

begin
{

    #$ErrorActionPreference = "Stop" #Stop, *Continue*, SilentlyContinue
    #$VerboseActionPreference = "Continue" #Stop, Continue, *SilentlyContinue*

    function BuildPropertyComparer
    {
        param (
            [Parameter(Mandatory)]
            [string[]]$Property,

            [Parameter()]
            [switch]$CaseSensitive
        )
        #Build a string to calculate the hashcode of multiple properties of an object
        #This is a simple XOR of the hashcodes of each of the properties
        #This is a more complex example that is not used here, but left for reference
        write-verbose "Building Property Comparer for $($Property -join ', ')"


        #the apostrophes on the properties allows support for props with spaces
        if ($CaseSensitive)
        {
            $equalsStr = ($property | ForEach-Object { "(`$x.'$_' -ceq `$y.'$_')" } )
            $HashCalcs = ($property | ForEach-Object { @"
        [int]`$hash$_ = if (`$null -eq `$record.'$_') {
            0
        } else {
            `$record.'$_'.GetHashCode()
        }
"@
                })
        }
        else
        {
            $equalsStr = ($property | ForEach-Object { "(`$x.'$_' -ieq `$y.'$_')" } )
            #todo need to add some sort of type check
            $HashCalcs = ($property | ForEach-Object { @"
        [int]`$hash$_ = if (`$null -eq `$record.'$_') {
            0
        } elseif (`$record.'$_'.gettype().name -eq 'String') {
            `$record.'$_'.tolower().GetHashCode()
        } else {
            `$record.'$_'.GetHashCode()
        }
"@
                })
        }

        # $hashStr = "[int]({0})" -f (($property | %{ "([string](record.$_)).GetHashCode()" }) -join ' ^ ')
        $HashIDs = $property | ForEach-Object { "`$hash$_" }
        $HashStr = 'return [int]({0});' -f ($HashIDs -join ' -bxor ')

        $cls = @"
class CustomComparer:Collections.Generic.IEqualityComparer[System.object]
{
    [bool]Equals([System.object]`$x, [System.object]`$y)
    {
        #If the objects are the same, return true
        if ([Object]::ReferenceEquals(`$x , `$y)) {return `$true}

        #I'm not sure the statements below are true, but leaving it for future consideration.
        # These comparison tasks could make it a little faster in certain scnearios,
        # but in this specific scenario we know that they shouldn't ever be null or  the same object. removing for speed
        #if ([Object]::ReferenceEquals(`$x, `$null) -or [Object]::ReferenceEquals(`$y, `$null)) {return false; };

        return (
            $($equalsStr -join " -and `n            ")
        )
    }

    [int]GetHashCode([System.Object] `$record)
    {
        if ([Object]::ReferenceEquals(`$record, `$null)) {return 0}

$($HashCalcs  -join "`n`n")

        $HashStr
    }
}
"@
        write-output $cls
    }

} #/begin

process
{
    #$PSBoundParameters.containskey('') to determine if value was specified for parameter
    #switch ($pscmdlet.parametersetname) {"Group1" {} "Group2" {} }

    if ($property)
    {
        $comparerStr = BuildPropertyComparer -Property $property -CaseSensitive:$CaseSensitive
        Write-Verbose $comparerStr
        Invoke-Expression $comparerStr
        $comparer = [CustomComparer]::new()
    }
    else
    {
        $comparer = $null
    }

    # $toIEnumerable = [Linq.Enumerable].GetMethod('Cast').MakeGenericMethod([System.Object])
    # $cA = $toIEnumerable.Invoke($null, (, $CollectionA))
    # $cB = $toIEnumerable.Invoke($null, (, $CollectionB))

    $returndata = [pscustomobject] @{
        OnlyA  = [System.Collections.Generic.List[System.Object]]::new(([Linq.Enumerable]::Except($collectionA, $collectionB, $comparer)))
        OnlyB  = [System.Collections.Generic.List[System.Object]]::new(([Linq.Enumerable]::Except($collectionB, $collectionA, $comparer)))
        #This returns the objects from array1 that are equal, necessary because they might have properties we didn't test
        EqualA = [System.Collections.Generic.List[System.Object]]::new(([Linq.Enumerable]::Intersect($collectionA, $collectionB, $comparer)))
        EqualB = [System.Collections.Generic.List[System.Object]]::new(([Linq.Enumerable]::Intersect($collectionB, $collectionA, $comparer)))
        #We include the properties tested with the object, so that the user can see what was tested
        Tested = $property
    }
    #This one Equal property returns only the properties tested with
    $returndata | Add-Member -Name 'Equal' -MemberType ScriptProperty -Value { $this.EqualA | Select-Object $this.tested }
    #These are for backwards compatibility
    $returndata | Add-Member -Name 'OnlyColA' -MemberType ScriptProperty -Value { $this.OnlyA }
    $returndata | Add-Member -Name 'OnlyColB' -MemberType ScriptProperty -Value { $this.OnlyB }

    $defaultDisplaySet = 'Equal', 'OnlyA', 'OnlyB'
    $defaultDisplayPropertySet = New-Object System.Management.Automation.PSPropertySet('DefaultDisplayPropertySet', [string[]]$defaultDisplaySet)
    $PSStandardMembers = [System.Management.Automation.PSMemberInfo[]]@($defaultDisplayPropertySet)
    $returndata | Add-Member MemberSet PSStandardMembers $PSStandardMembers

    Write-Output $returndata

} #/process

end
{
    #useful for cleanup, or to write-output whatever you want to return to the user
} #/end


#DEV
###############################################################
# Parameter Template
###############################################################
<#
    #For each ParameterSet, you must specify a Parameter block
    #Parameters with no ParameterSetName are available to ALL ParameterSets
    [Parameter(
        Position=0, #implicit parameter ordering
        Mandatory, #indicates a required parameter.  Can use multiple parameter sets to make optional in certain cases
        ParameterSetName="Group1", #If using ParameterSets (different groups of required parameters)
        ValueFromPipeline, #the piped inputs will be used here
        ValueFromPipelineByPropertyName, #the property name of the piped inputs will be used here ($files.PATH)
        HelpMessage='What computer name would you like to target?', #especially useful for mandatory, this will be the prompt presented.
        ValueFromRemainingArgument=$true #this pushes all remaining unassigned variables into this parameter.
    )]
    #mandatory, valuefrom* can have "=$true/$false" but like a switch, it's implicit. v2 requires explicit =$true/$false
    [SupportsWildcards()]
    [Alias('MachineName')] #Can use -MachineName in this example instead of Param1 and it will still be recognized, helpful for ValueFromPipelineByPropertyName.  Is array-based, so ('MachineName','ServerName') is valid.
    [ValidateCount(2,5)] #number of items in collection, if you provided 1 item or 6 items in an array, it would error.  Typically used with arrays [vartype[]]
    [ValidateLength(3,30)] #the length of the object. Typically for strings, if the string was 'AB', it would error
    [ValidatePattern("regexpattern")] #RegexPattern to match.  usually for string, must match the regex pattern equivalent to ($param -match $regex)
    [ValidateRange(1,100)] #typically a number, -1 or 1000 would error
    [ValidateScript({$_ -gt (10)})] #must return $true/$false, this would require the number to be greater than 10
    [ValidateSet('Input','Output','Both')] #any set of values you want here.  These are the only accepted values for this input.  Can also be effectively combined with arrays.  Not case sensitive.
    [ValidateNotNullOrEmpty()] #Common to use, Mandatory doesn't enforce content, only the existence of a parameter, this can be used to ensure the user provides something beyond $null or ""
    [ValidateNotNull()] #same as ValidateNotNullOrEmpty, but only prevents $null
    [AllowNull()] #effectively reverse of ValidateNotNullOrEmpty
    [AllowEmptyString()]
    [AllowEmptyCollection()]
    #WEBJEA-Multiline #WebJEA specific directive, this forces webjea to show a multiline input field
    #WEBJEA-DateTime #WebJEA specific directive, this forces webjea to show prompt for date AND time, not just date when using variable [datetime]
    [string[]]$ComputerName, #accepts multiple, typically use a foreach in process{}
    [string]$ComputerName, #only one
#    common: [switch]/[boolean], [int]/[int32]/[byte]/[uint]/[uint64], [pscredential], [psobject], [float]/[double], [datetime] many others possible and most support [] within to accept multiple in an array.
#    can also specify any .NET object type (e.g. System.Generic.Collections.List)
#    note: switch and boolean are not treated the same, switches are called with -paramname[:$true/false] where boolean are called -paramname $true/$false
#    can always specify default values after the variable e.g. [string]$computername = $env:computername or (get-date) or most anything in powershell, but you can't see the other variables yet.  It can however reference variables in the parent scope.
#DynamicParam is available, but an advanced topic not covered here.  see: https://docs.microsoft.com/en-us/powershell/module/microsoft.powershell.core/about/about_functions_advanced_parameters?view=powershell-5.1#dynamic-parameters
#>
#/DEV


