#I’ve built a script to compare collections, especially large collections, in a flexible and fast way.

#We can compare the collections by hand, iterating through each collection.  To do this you have to build a scriptblock to do the comparison.  This is slow.
#Hashing can make this faster, but you have to pre-calculate the hashes which comes with it’s own pain when you have dozens of properties to compare.
#Hashing and comparing large datasets is still very slow.  Looking to see if $hashA is in $hashSet is pretty fast.  Trying to identify every equal hash and every different hash acrosss large datasets is painful. and slow. so. so slow.

#Enter LINQ
#LINQ is a .net native query tool.  It can do lots of stuff, but we’re going to focus on just Equals and XXXXXX.

$col1 = Import-Csv .\tests\g1.csv
$col2 = Import-Csv .\tests\g2.csv
$props = 'group', 'id', 'data'
$col1 #sample input

$result = & .\Compare-Collections.ps1 $col1 $col2 $props
$result.summary
$result | gm -membertype noteproperty,scriptproperty | select name,MemberType
$result.equal_col1
$result.diff_col1
$result.diff_col1
$result | Format-List *

#But we can name our sources for convenience
$namedResult = & .\Compare-Collections.ps1 $col1 $col2 $props -col1name src -col2Name dst
$namedresult.diff_src

#We can also do a case-sensitive comparison
$namedresult.summary
$caseResult = & .\Compare-Collections.ps1 $col1 $col2 $props -col1name src -col2Name dst -casesensitive
$caseresult.summary

#We don’t even have to tell the script which properties we want
#be aware, this will only work when the properties are consistent.  It just takes the first element of each collection and looks for matching properties, it also only uses noteproperties since 99% of the time scriptproperties are built from noteproperties.
$nopropResult = & .\Compare-Collections.ps1 $col1 $col2
$nopropResult.compared

#So far, these examples show convenience, but let’s see how we can save time.
$largeCol1 = Import-Csv .\tests\large1.csv #200k records
$largeCol2 = Import-Csv .\tests\large2.csv #200k records, but slightly different
measure-command {$largeResult = & .\Compare-Collections.ps1 $largeCol1 $largeCol2} #3m0s
$largeresult.summary

#For comparison, I ran this same comparison against the two previous ways I used to do this
#With native where blocks and index tracking
$nativeResult = & .\Compare-CollectionsNative.ps1 $largeCol1 $largeCol2 $largeProps #1h4m


# https://www.red-gate.com/simple-talk/development/dotnet-development/high-performance-powershell-linq/


#
# github.com/markdomansky/PSLINQ
#