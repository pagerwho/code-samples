$SQLInstances = @("localhost") # For safety purposes, each instance should be transactionally seperated in insulated loop.
[xml]$Job = Get-Content -Path C:\Temp\MyJob.xml
foreach ($SQLInstance in $SQLInstances) {
    # Grab our schedules
    $Schedules = $Job.SelectNodes("//Schedule")
        
    # Grab our steps
    $Steps = $Job.SelectNodes("//Step") | Sort-Object { $_.Id }

    if ($null -eq (Get-DbaAgentJob -SqlInstance $SQLInstance -Job $Job.Job.Name)) {
        
        # Create the Category if it doesn't exist
        if ($null -eq (Get-DbaAgentJobCategory -SqlInstance $SQLInstance -Category $Job.Job.Category)) {
            New-DbaAgentJobCategory -SqlInstance $SQLInstance -Category $Job.Job.Category
        }
        
        # Create a stub job with valid schedules attached already
        New-DbaAgentJob -SqlInstance $SQLInstance -Job $Job.Job.Name -Schedule (Get-DbaAgentSchedule -SqlInstance $SQLInstance -Schedule $Schedules.Name).Name -Disabled
        
        #Build our schedules
        foreach ($Schedule in $Schedules) {
            $ScheduleParam = @{
                SQLInstance = $SQLInstance
                Schedule = $Schedule.Name
                Job = $Job.Job.Name
                FrequencyInterval = $Schedule.FrequencyIntervals.FrequencyInterval.Value
                FrequencyType = $Schedule.FrequencyType
                FrequencyRecurrenceFactor = $Schedule.FrequencyRecurrenceFactor
                FrequencySubdayType = $Schedule.FrequencySubdayType
                FrequencySubdayInterval = $Schedule.FrequencySubdayInterval
                StartDate = $Schedule.StartDate
                StartTime = $Schedule.StartTime
                EndDate = $Schedule.EndDate
                EndTime = $Schedule.EndTime
            }
            if ($null -eq (Get-DbaAgentSchedule -SqlInstance $SQLInstance -Schedule $Schedule.Name)) {
                if ($Schedule.Disabled -eq "0") {
                    "Creating $($Job.Job.Name): Schedule $($Schedule.Name), Enabled"
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        New-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        New-DbaAgentSchedule @ScheduleParam
                    }
                }
                else {
                    "Creating $($Job.Job.Name): Schedule $($Schedule.Name), Disabled"
                    $ScheduleParam.Add("Disabled")
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        New-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        New-DbaAgentSchedule @ScheduleParam
                    }
                }
                
            }
            else {
                # Need to set the schedules, properties could be changing and existing schedule
                # If this happens, the schedule WILL NOT update. (Re-)attach the schedule at the end.
                if ($Schedule.Disabled -eq "0") {
                    "Updating $($Job.Job.Name): Schedule $($Schedule.Name), Enabled"
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                }
                else {
                    "Creating $($Job.Job.Name): Schedule $($Schedule.Name), Disabled"
                    $ScheduleParam.Add("Disabled")
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                }
            }
        }

        # first pass of steps, will need to run a set after to handle interleaving
        foreach ($Step in $Steps) {
            "Creating Steps For Job $($Job.Job.Name) [STEP]: $($Step.Name)."
            New-DbaAgentJobStep -SqlInstance $SQLInstance `
                -Job $Job.Job.Name `
                -StepId $Step.Id `
                -StepName $Step.Name `
                -Subsystem $Step.Subsystem `
                -SubsystemServer $Step.SubsystemServer `
                -Command $Step.Command `
                -CmdExecSuccessCode $Step.CmdExecSuccessCode `
                -Database $Step.Database `
                -DatabaseUser $Step.DatabaseUser `
                -RetryAttempts $Step.RetryAttempts `
                -RetryInterval $Step.RetryInterval `
                -OutputFileName $Step.OutputFileName `
                -Flag $Step.Flags.Flag.Value `
                -ProxyName $Step.ProxyName
        }

        # second pass of steps, to handle interleaving
        foreach ($Step in $Steps) {
            "Finalizing Steps For Job $($Job.Job.Name) [STEP]: $($Step.Name). Adding Success/Fail Actions."
            Set-DbaAgentJobStep -SqlInstance $SQLInstance `
                -Job $Job.Job.Name
                -StepName $Step.Name `
                -Subsystem $Step.Subsystem `
                -SubsystemServer $Step.SubsystemServer `
                -Command $Step.Command `
                -CmdExecSuccessCode $Step.CmdExecSuccessCode `
                -OnSuccessAction $Step.OnSuccessAction `
                -OnSuccessStepId $Step.OnSuccessStepId `
                -OnFailAction $Step.OnFailAction `
                -OnFailStepId $Step.OnFailStepId `
                -Database $Step.Database `
                -DatabaseUser $Step.DatabaseUser `
                -RetryAttempts $Step.RetryAttempts `
                -RetryInterval $Step.RetryInterval `
                -OutputFileName $Step.OutputFileName `
                -Flag $Step.Flags.Flag.Value `
                -ProxyName $Step.ProxyName
        }

        $JobParam = @{
            SQLInstance = $SQLInstance
            Job = $Job.Job.Name 
            Schedule = $Schedules.Name 
            Description = $Job.Job.Description 
            StartStepId = $Job.Job.StartStepId 
            Category = $Job.Job.Category 
            OwnerLogin = $Job.Job.OwnerLogin 
            EventLogLevel = $Job.Job.EventLogLevel 
            EmailLevel = $Job.Job.EmailLevel 
            PageLevel = $Job.Job.PageLevel 
            EmailOperator = $Job.Job.EmailOperator 
            NetsendOperator = $Job.Job.NetsentOperator 
            PageOperator = $Job.Job.PageOperator 
            DeleteLevel = $Job.Job.DeleteLevel
        }
        # Finish the job creation
        if ($Job.Job.Disabled -eq 0) {
            $JobParam.Add("Enabled",$true)
            "Enable Job [$($Job.Job.Name)], set remaining properties"
            Set-DbaAgentJob @JobParam
        }
        else {
            $JobParam.Add("Disabled",$true)
            "Disable Job [$($Job.Job.Name)], set remaining properties"
            Set-DbaAgentJob @JobParam
        }
    }
    else {
        # Check for a category update
        if ((Get-DbaAgentJob -SqlInstance $SQLInstance -Job $Job.Job.Name).Category -ne $Job.Job.Category)
        {
            if($null -ne (Get-DbaAgentJobCategory -SqlInstance $SQLInstance -Category $Job.Job.Category))
            {
                "Existing Job $($Job.Job.Name): Updating to Existing Category: $($Job.Job.Category)."
                Set-DbaAgentJob -SqlInstance $SQLInstance -Job $Job.Job.Name -Category $Job.Job.Category
            }
            else {
                "Existing Job $($Job.Job.Name): Creating New Category: $($Job.Job.Category)."
                New-DbaAgentJobCategory -SqlInstance $SQLInstance -Category $Job.Job.Category    
            }
        }

        #Build our schedules
        foreach ($Schedule in $Schedules) {
            # Check to see if the schedule exists (New vs. Set)
            "Existing Job $($Job.Job.Name): Checking Schedule: $($Schedule.Name)."
            
            $ScheduleParam = @{
                SQLInstance = $SQLInstance
                Schedule = $Schedule.Name
                Job = $Job.Job.Name
                FrequencyInterval = $Schedule.FrequencyIntervals.FrequencyInterval.Value
                FrequencyType = $Schedule.FrequencyType
                FrequencyRecurrenceFactor = $Schedule.FrequencyRecurrenceFactor
                FrequencySubdayType = $Schedule.FrequencySubdayType
                FrequencySubdayInterval = $Schedule.FrequencySubdayInterval
                StartDate = $Schedule.StartDate
                StartTime = $Schedule.StartTime
                EndDate = $Schedule.EndDate
                EndTime = $Schedule.EndTime
            }
            if($null -eq (Get-DbaAgentSchedule -SqlInstance $SQLInstance -Schedule $Schedule.Name)) {
                "Unable to locate schedule: $($Schedule.Name), Creating New Schedule."
                # Check to see what parameter splat (Enable/Disable,FrequencyRelativeInterval) we need to use (potential refactor)
                if ($Schedule.Disabled -eq "0") {
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        "Creating Schedule ($($Schedule.Name)): Enabled, relative interval NOT needed"
                        New-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        "Creating Schedule ($($Schedule.Name)): Enabled, relative interval needed"
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        New-DbaAgentSchedule @ScheduleParam
                    }
                }
                else {
                    $ScheduleParam.Add("Disabled",$true)
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        "Creating Schedule ($($Schedule.Name)): DISABLED, relative interval NOT needed"
                        New-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        "Creating Schedule ($($Schedule.Name)): DISABLED, relative interval needed"
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        New-DbaAgentSchedule @ScheduleParam
                    }
                }
                
            }
            else {
                "Found Schedule: $($Schedule.Name), Updating."
                # Need to set the schedules, properties could be changing and existing schedule
                # If this happens, the schedule WILL NOT update. (Re-)attach the schedule at the end.
                
                # Check to see what parameter splat (Enable/Disable,FrequencyRelativeInterval) we need to use (potential refactor)
                if ($Schedule.Disabled -eq "0") {
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        "Altering Schedule ($($Schedule.Name)): Enabled, relative interval NOT needed"
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        "Altering Schedule ($($Schedule.Name)): Enabled, relative interval needed"
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                }
                else {
                    $ScheduleParam.Add("Disabled",$true)
                    if ("" -eq $Schedule.FrequencyRelativeInterval) {
                        "Altering Schedule ($($Schedule.Name)): DISABLED, relative interval NOT needed"
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                    else {
                        "Altering Schedule ($($Schedule.Name)): DISABLED, relative interval needed"
                        $ScheduleParam.Add("FrequencyRelativeInterval",$Schedule.FrequencyRelativeInterval)
                        Set-DbaAgentSchedule @ScheduleParam
                    }
                }
            }
        }

        # Check for job step order (ID changes), name changes, and step removals.
        # Need to remove and re-add if this occurs for simplification
        $JobSteps = (Get-DbaAgentJobStep -SqlInstance $SqlInstance -Job $Job.Job.Name) | Sort-Object $_.ID
        $i = 0
        $j = ($Steps | Measure-Object).Count - 1
        $RemoveSteps = $false
        if($null -ne $JobSteps)
        {
            "Existing Job $($Job.Job.Name): Checking for Step ID OR Name Changes."
            while ($i -le $j) {
                if (($JobSteps[$i].ID -ne $Steps[$i].Id) -or ($JobSteps[$i].ID -eq $Steps[$i].Id -and $JobSteps[$i].Name -ne $Steps[$i].Name)) {
                    "Checking Step ID ($($JobSteps[$i].ID)):$($JobSteps[$i].Name) against XML Step ID($($Steps[$i].ID)):$($Steps[$i].Name)."
                    $RemoveSteps = $true
                    # We can stop our checks after the first hit.
                    break
                }
                $i++
            }
        }
        else {
            "No Steps Found. Bypass Checks."
            $RemoveSteps = $true
        }

        # If we found step ID changes, remove all of the job steps. Easier than nested loops.
        if ($true -eq $RemoveSteps) {
            "Found Step ID or Step Name mismatches. Removing Current Job Steps to Allow Recreation."
            foreach ($JobStep in $JobSteps) {
                "Removing Steps From $($Job.Job.Name) [STEP]: $($Step.Name)."
                Remove-DbaAgentJobStep -SqlInstance $SqlInstance `
                    -Job $Job.Job.Name `
                    -StepName $JobStep.Name
            }

            # first pass of steps, will need to run a set after to handle interleaving
            foreach ($Step in $Steps) {
                "Creating Steps For Job $($Job.Job.Name) [STEP]: $($Step.Name)."
                New-DbaAgentJobStep -SqlInstance $SQLInstance `
                    -Job $Job.Job.Name `
                    -StepId $Step.Id `
                    -StepName $Step.Name `
                    -Subsystem $Step.Subsystem `
                    -SubsystemServer $Step.SubsystemServer `
                    -Command $Step.Command `
                    -CmdExecSuccessCode $Step.CmdExecSuccessCode `
                    -Database $Step.Database `
                    -DatabaseUser $Step.DatabaseUser `
                    -RetryAttempts $Step.RetryAttempts `
                    -RetryInterval $Step.RetryInterval `
                    -OutputFileName $Step.OutputFileName `
                    -Flag $Step.Flags.Flag.Value `
                    -ProxyName $Step.ProxyName
            }

            # second pass of steps, to handle interleaving
            foreach ($Step in $Steps) {
                "Finalizing Steps For Job $($Job.Job.Name) [STEP]: $($Step.Name). Adding Success/Fail Actions."
                Set-DbaAgentJobStep -SqlInstance $SQLInstance `
                    -Job $Job.Job.Name `
                    -StepName $Step.Name `
                    -Subsystem $Step.Subsystem `
                    -SubsystemServer $Step.SubsystemServer `
                    -Command $Step.Command `
                    -CmdExecSuccessCode $Step.CmdExecSuccessCode `
                    -OnSuccessAction $Step.OnSuccessAction `
                    -OnSuccessStepId $Step.OnSuccessStepId `
                    -OnFailAction $Step.OnFailAction `
                    -OnFailStepId $Step.OnFailStepId `
                    -Database $Step.Database `
                    -DatabaseUser $Step.DatabaseUser `
                    -RetryAttempts $Step.RetryAttempts `
                    -RetryInterval $Step.RetryInterval `
                    -OutputFileName $Step.OutputFileName `
                    -Flag $Step.Flags.Flag.Value `
                    -ProxyName $Step.ProxyName
            }
        }
        else {
            # Re-cache our job steps for altering the existing steps
            "No Step Order or Step Name Changes Found. Altering Existing Job Steps."
            $JobSteps = (Get-DbaAgentJobStep -SqlInstance $SqlInstance -Job $Job.Job.Name) | Sort-Object $_.ID
            $i = 0
            $j = ($Steps | Measure-Object).Count - 1
            while ($i -le $j) {
                "Altering $($Job.Job.Name) [STEP]: $($Steps[$i].Name)."
                Set-DbaAgentJobStep -SqlInstance $SqlInstance `
                    -Job $Job.Job.Name `
                    -StepName $JobSteps[$i].Name `
                    -NewName $Steps[$i].Name `
                    -Subsystem $Steps[$i].Subsystem `
                    -SubsystemServer $Steps[$i].SubsystemServer `
                    -Command $Steps[$i].Command `
                    -CmdExecSuccessCode $Steps[$i].CmdExecSuccessCode `
                    -OnSuccessAction $Steps[$i].OnSuccessAction `
                    -OnSuccessStepId $Steps[$i].OnSuccessStepId `
                    -OnFailAction $Steps[$i].OnFailAction `
                    -OnFailStepId $Steps[$i].OnFailStepId `
                    -Database $Steps[$i].Database `
                    -DatabaseUser $Steps[$i].DatabaseUser `
                    -RetryAttempts $Steps[$i].RetryAttempts `
                    -RetryInterval $Steps[$i].RetryInterval `
                    -OutputFileName $Steps[$i].OutputFileName `
                    -Flag $Steps[$i].Flags.Flag.Value `
                    -ProxyName $Steps[$i].ProxyName
                $i++
            }
            $i = ($JobSteps | Measure-Object).Count
            while ($i -lt $j) {
                "Adding New Step From XML StepID($($Steps.Id)):$($Steps.Name)"
                New-DbaAgentJobStep -SqlInstance $SqlInstance `
                    -Job $Job.Job.Name `
                    -StepId $Steps[$i].Id `
                    -StepName $Steps[$i].Name `
                    -Subsystem $Steps[$i].Subsystem `
                    -SubsystemServer $Steps[$i].SubsystemServer `
                    -Command $Steps[$i].Command `
                    -CmdExecSuccessCode $Steps[$i].CmdExecSuccessCode `
                    -OnSuccessAction $Steps[$i].OnSuccessAction `
                    -OnSuccessStepId $Steps[$i].OnSuccessStepId `
                    -OnFailAction $Steps[$i].OnFailAction `
                    -OnFailStepId $Steps[$i].OnFailStepId `
                    -Database $Steps[$i].Database `
                    -DatabaseUser $Steps[$i].DatabaseUser `
                    -RetryAttempts $Steps[$i].RetryAttempts `
                    -RetryInterval $Steps[$i].RetryInterval `
                    -OutputFileName $Steps[$i].OutputFileName `
                    -Flag $Steps[$i].Flags.Flag.Value `
                    -ProxyName $Steps[$i].ProxyName
                $i++
            }   
        }

        $JobParam = @{
            SQLInstance = $SQLInstance
            Job = $Job.Job.Name 
            Schedule = $Schedules.Name 
            Description = $Job.Job.Description 
            StartStepId = $Job.Job.StartStepId 
            Category = $Job.Job.Category 
            OwnerLogin = $Job.Job.OwnerLogin 
            EventLogLevel = $Job.Job.EventLogLevel 
            EmailLevel = $Job.Job.EmailLevel 
            PageLevel = $Job.Job.PageLevel 
            EmailOperator = $Job.Job.EmailOperator 
            NetsendOperator = $Job.Job.NetsentOperator 
            PageOperator = $Job.Job.PageOperator 
            DeleteLevel = $Job.Job.DeleteLevel
        }
        # Finish the job alteration
        if ($Job.Job.Disabled -eq 0) {
            $JobParam.Add("Enabled",$true)
            "Enable Job [$($Job.Job.Name)], set remaining properties"
            Set-DbaAgentJob @JobParam
        }
        else {
            $JobParam.Add("Disabled",$true)
            "Disable Job [$($Job.Job.Name)], set remaining properties"
            Set-DbaAgentJob @JobParam
        }
    }
}