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
Author:           github/markdomansky
Creation Date:    2024-07-07 15:07
History:
    2024-07-07 15:07, markdomansky, Created script


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

    [Parameter(Position = 0)]
    [Alias('A', 'ColA', 'Collection1')]
    [Object[]]$CollectionA,

    [Parameter(Position = 1)]
    [Alias('B', 'ColB', 'Collection2')]
    [Object[]]$CollectionB,

    [Parameter(Position = 2, Mandatory)]
    [Alias('CompareProperties')]
    [ValidateNotNullOrEmpty()]
    [String[]]$CompareProperty,

    [Parameter(Position = 3)]
    [Alias('ColAProperties')]
    [ValidateNotNullOrEmpty()]
    [String[]]$CollectionAProperty,

    [Parameter(Position = 4)]
    [Alias('ColBProperties')]
    [ValidateNotNullOrEmpty()]
    [String[]]$CollectionBProperty,

    [Parameter()]
    [Switch]$TreatWhitespaceAsNull,

    [Parameter()]
    [switch]$HonorNumericDataTypes,

    [Parameter()]
    [Switch]$CaseSensitive,

    [Parameter()]
    [switch]$LeftInnerJoinOnly

) #/param

begin
{

    #$ErrorActionPreference = "Stop" #Stop, *Continue*, SilentlyContinue
    #$VerboseActionPreference = "Continue" #Stop, Continue, *SilentlyContinue*

    function BuildKeySelectorHash
    {
        param (
            [Parameter(Mandatory)]
            [string[]]$Property,

            [Parameter()]
            [Switch]$TreatWhitespaceAsNull,

            [Parameter()]
            [switch]$HonorNumericDataTypes,

            [Parameter()]
            [switch]$CaseSensitive
        )

        #Build a string to calculate the hashcode of multiple properties of an object
        #This is a simple XOR of the hashcodes of each of the properties
        #This is a more complex example that is not used here, but left for reference
        Write-Verbose "Building Key Selector Hash for $($Property -join ', ')"
        $tolower = '.tolower()'
        if ($CaseSensitive) { $tolower = '' }

        $NullCheck = '$null -eq ('
        if ($TreatWhitespaceAsNull)
        {
            $NullCheck = '[string]::IsNullOrWhitespace('
        }

        $propSubFuncArr = [System.Collections.Generic.List[System.Object]]::new()
        foreach ($p in $property)
        {
            $psfNumStr = ''
            if ($HonorNumericDataTypes)
            {
                $psfNumStr = @"

    elseif (`$args[0]."$p".gettype() -match '^(S?Byte|U?Int(\d{2})?|BigInteger|Decimal|Double|Single)$')
    {   #Treat as numeric
        `$dataArr.Add(`$args[0]."$p")
    }
"@
            }
            $psfStr = @"
    if ($NullCheck `$args[0]."$p"))
    {   #Treat as null
        `$dataArr.add(`$null)
    }$psfNumStr
    else
    {   #Treat as string
        `$dataArr.Add(`$args[0]."$p".tostring()$tolower)
    }
"@
            $propSubFuncArr.add($psfStr)
        }
        $PropSubFuncStr = $PropSubFuncArr -join "`n`n"

        $StrOut = @"
[Func[Object,uint64]] {
    `$dataArr = [System.Collections.Generic.List[System.Object]]::new() #we want an ordered list of the property values

    #Add compared properties to the ordered list, depending on the type
$PropSubFuncStr

    `$dataStr = `$dataArr | convertto-json -depth 0 -compress #conver to json to get a consistent string representation for hashing
    # write-host `$dataStr
    `$dataBytes = [System.Text.Encoding]::UTF8.GetBytes(`$dataStr) #convert to bytes
    # write-host `$dataBytes.length
    `$ByteHash = [System.Security.Cryptography.HashAlgorithm]::Create('sha256').ComputeHash(`$dataBytes) #hash
    [uint64]`$retval = [BitConverter]::ToUint64(`$bytehash,0) #we just want a uint64 but it should be unique within the scale of 64bits
    # write-host `$retval
    return `$retval
}
"@

        Write-Output $StrOut
    }

    function BuildResultDelegate
    {
        param(
            [Parameter(Mandatory)]
            [string[]]$CompareProperty,

            [Parameter()]
            [string[]]$CollectionAProperty,

            [Parameter()]
            [string[]]$CollectionBProperty
        )

        $ComparePropertyArr = $CompareProperty | ForEach-Object { "`t`"$_`" = `$args[0].`"$_`"" }
        $ComparePropertyStr = $ComparePropertyArr -join "`n"

        #Remove duplicates from CompareProperty
        $ColAPropArr = $CollectionAProperty | ?{$_ -notin $compareproperty -and $_} | ForEach-Object { "`t`"$_`" = `$args[0].`"$_`"" }
        # if ($ColAPropArr.count -gt 0) {$ColAPropStr = $ColAPropArr -join "`n"} else {$ColAPropStr = ''}
        $ColAPropStr = $ColAPropArr -join "`n"

        #Remove duplicates from CompareProperty
        $ColBPropArr = $CollectionBProperty | ?{$_ -notin $compareproperty -and $_} | ForEach-Object { "`t`"$_`" = `$ColB.`"$_`"" }
        # if ($ColBPropArr.count -gt 0) {$ColBPropStr = $ColBPropArr -join "`n"} else {$ColBPropStr = ''}
        $ColBPropStr = $ColBPropArr -join "`n"

        $StrOut = @"
[Func[Object,[Collections.Generic.IEnumerable[Object]],Object]] {
    #`$args[0] = ColA, `$args[1] = ColB (ColB could have multiple matches)
    #We have to convert `$args[1] to something powershell can use easily
    [System.Collections.Generic.List[System.Object]]`$ColB = `$args[1]

    #Meta data to show where the object came from
    if (`$ColB.Count -eq 0) {`$LinqJoin = 'Left'} else {`$LinqJoin = 'Inner'}

    #Output of data
    write-output ([pscustomobject]@{

    #Shared/Compare Properties
$ComparePropertyStr

    #ColA Properties
$ColAPropStr

    #ColB Properties
$ColBPropStr

    #JoinStatus
        _LinqJoin = `$LinqJoin
        _LinqJoinCount = `$ColB.Count
    })

}
"@
        Write-Output $StrOut
    }

} #/begin

process
{
    #$PSBoundParameters.containskey('') to determine if value was specified for parameter
    #switch ($pscmdlet.parametersetname) {"Group1" {} "Group2" {} }
    if ($null -eq $CollectionB) { return $CollectionA }
    if ($null -eq $CollectionA) { return $CollectionB }

    ##### Get the Inner Join results
    $KeyFuncStr = BuildKeySelectorHash -Property $CompareProperty -CaseSensitive:$CaseSensitive -TreatWhitespaceAsNull:$TreatWhitespaceAsNull -HonorNumericDataTypes:$HonorNumericDataTypes
    write-verbose "##### Invoking KeyFuncStr: `n$KeyFuncStr"
    $KeyFunc = Invoke-Expression $KeyFuncStr
    $OutputFuncStr = BuildResultDelegate -CompareProperty $CompareProperty -CollectionAProperty $CollectionAProperty -CollectionBProperty $CollectionBProperty
    write-verbose "##### Invoking OutputFuncStr: `n$OutputFuncStr"
    $OutputFunc = Invoke-Expression $OutputFuncStr

    [System.Collections.Generic.List[System.Object]]$InnerFullJoin = [Linq.Enumerable]::GroupJoin($CollectionA, $CollectionB, $KeyFunc, $KeyFunc, $OutputFunc)

    $results = [System.Collections.Generic.List[System.Object]]::new()
    $results.AddRange($InnerFullJoin)

    ##### Get the Exceptions
    if (-not $LeftInnerJoinOnly) {

    # #We're doing this rather than an actual outer join so that we aren't modifying the original objects.  Otherwise, we'd need to add a _LinqJoin property to the originals.
    [System.Collections.Generic.List[System.Object]]$RightOuterJoin = [Linq.Enumerable]::GroupJoin($CollectionB, $CollectionA, $KeyFunc, $KeyFunc, $OutputFunc)
    # Now we just filter munge the value to what it should be.
    [Func[object, bool]]$ROJFilter = { param($obj); return ($obj.'_LinqJoin' -eq 'Left') }
    # $RightOuterJoin = $RightOuterJoin | ?{$_.'_LinqJoin' -eq 'Left'}
    [System.Collections.Generic.List[System.Object]]$RightOuterJoin = [Linq.Enumerable]::Where($RightOuterJoin, $ROJFilter)
    $RightOuterJoin | %{ $_.'_LinqJoin' = 'Right'}


    $results.AddRange($RightOuterJoin)
    }


    Write-Output $results

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


