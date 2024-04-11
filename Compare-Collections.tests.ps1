#requires -module @{ModuleName='Pester';ModuleVersion='5.0'}

Describe 'Compare-Collections.ps1' {
    Context 'Compare Collections' {
        BeforeAll {
            $script:col1 = Import-Csv $PSScriptRoot\tests\g1.csv
            $script:col2 = Import-Csv $PSScriptRoot\tests\g2.csv
            $script:props = 'group', 'id', 'data'

            $script:ColEqual = $script:col1 | Where-Object { $_.g1 -eq 'eq' }
            $script:col1Only = $script:col1 | Where-Object { $_.g1 -ne 'eq' }
            $script:col2Only = $script:col2 | Where-Object { $_.g2 -ne 'eq' }
            function TestColMatch($col1, $col2, $props)
            {
                $c1 = $col1 | Sort-Object group
                $c2 = $col2 | Sort-Object group
                $cnt = $c1.Count
                for ($idx = 0; $idx -lt $cnt; $idx++)
                {
                    foreach ($prop in $props)
                    {
                        if ($c1[$idx].$prop -ne $c2[$idx].$prop) { return $false }
                    }
                }
                return $true
            }
        }
        Context 'g1/g2.csv' {
            It 'Should return a dataset' {
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                $result | Should -BeOfType [PSCustomObject]
            }
            It 'Should returns 5 Base NoteProperties' {
                $resultProps = 'Equal1','Equal2','Only1','Only2','Tested'
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                $result | Get-Member -membertype NoteProperty | Select-Object -expand Name | Should -Be $resultProps
            }
            It 'Should returns 7 Default ScriptProperties' {
                $resultProps = 'Equal', 'Equal_colA', 'Equal_colB', 'Only_colA', 'Only_colB', 'Summary'
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                $result | Get-Member -MemberType ScriptProperty | Select-Object -expand Name | Should -Be $resultProps
            }
            It 'Should returns 7 Custom ScriptProperties' {
                $resultProps = 'Equal', 'Equal_X', 'Equal_Y', 'Only_X', 'Only_Y', 'Summary'
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props -Collection1Name X -Collection2Name Y
                $result | Get-Member -MemberType ScriptProperty | Select-Object -expand Name | Should -Be $resultProps
            }
            It 'Return 6 Equal records' {
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                $result.equal.count | Should -Be 6
                $result.equal1.count | Should -Be 6
                $result.equal2.count | Should -Be 6
                TestColMatch $result.equal $script:ColEqual $script:props | Should -BeTrue
                TestColMatch $result.equal1 $script:ColEqual $script:props | Should -BeTrue
                TestColMatch $result.equal2 $script:ColEqual $script:props | Should -BeTrue
            }
            It 'Returns 3 Only1 records' {
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                #Quick count check
                $result.Only1.count | Should -Be 3
                #Check every record
                TestColMatch $result.only1 $script:col1Only $script:props | Should -BeTrue
            }
            It 'Returns 3 Only2 records' {
                $result = & .\Compare-Collections.ps1 $script:col1 $script:col2 -Property $script:props
                #Quick count check
                $result.Only2.count | Should -Be 3
                #Check every record
                TestColMatch $result.only2 $script:col2Only $script:props | Should -BeTrue
            }
        }
    }
    # Context 'Edge Cases' {
    #     It 'Should return true when comparing two empty collections' {
    #         $result = Compare-Collections.ps1 @() @()
    #         $result | Should -Be $true
    #     }

    #     It 'Should return false when comparing an empty collection with a non-empty collection' {
    #         $result = Compare-Collections.ps1 @() @(1)
    #         $result | Should -Be $false
    #     }

    #     It 'Should return false when comparing a non-empty collection with an empty collection' {
    #         $result = Compare-Collections.ps1 @(1) @()
    #         $result | Should -Be $false
    #     }

    #     It 'Should return true when comparing two collections with the same elements' {
    #         $result = Compare-Collections.ps1 @(1, 2, 3) @(1, 2, 3)
    #         $result | Should -Be $true
    #     }

    #     It 'Should return false when comparing two collections with different elements' {
    #         $result = Compare-Collections.ps1 @(1, 2, 3) @(1, 2, 4)
    #         $result | Should -Be $false
    #     }

    #     It 'Should return false when comparing two collections with the same elements but in different order' {
    #         $result = Compare-Collections.ps1 @(1, 2, 3) @(3, 2, 1)
    #         $result | Should -Be $false
    #     }

    #     It 'Should return true when comparing two collections with the same elements but in different order and using the -IgnoreOrder switch' {
    #         $result = Compare-Collections.ps1 @(1, 2, 3) @(3, 2, 1) -IgnoreOrder
    #         $result | Should -Be $true
    #     }

    #     It 'Should return false when comparing two collections with the same elements but in different order and using the -IgnoreOrder switch' {
    #         $result = Compare-Collections.ps1 @(1, 2, 3) @(3, 2, 4) -IgnoreOrder
    #         $result | Should -Be $false
    #     }

    #     It 'Should return false when comparing two collections with the same elements but in different order and using the -IgnoreOrder switch' {
    #         $result = Compare-Collections.ps1.ps1 @(1, 2, 3) @(3, 2, 4) -IgnoreOrder
    #         $result | Should -Be $false
    #     }
    # }
    # Context 'Performance' {
    #     It 'Should compare two collections of 100000 elements in less than 1 second' {
    #         $col1 = Import-Csv "$psscriptroot\tests\testset1.csv"
    #         $col2 = Import-Csv "$psscriptroot\tests\testset2.csv"
    #         Measure-Command { Compare-Collections.ps1 $col1 $col2 } | Should -BeLessThan '00:00:01'
    #     }
    # }

}