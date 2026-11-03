#=============================================================================
# jtkey_daemon.tcl - resident xsdb key-injection daemon
#
#   Writes the PL AXI GPIO at 0x41200000 through the APU(DAP) JTAG target:
#     bit4..7 = K4/K5/K6/K7   bit8 = injection enable   bit9 = text panel
#   Polls jtkey.cmd (single integer) every 20 ms; on change it does a
#   read-modify-write so bit0/1/9 and the rest are preserved.
#
#   Start : jtkey_daemon_run.cmd      Exit : close that window / Ctrl-C
#=============================================================================
set D   [file dirname [file normalize [info script]]]
set F   "$D/jtkey.cmd"
set LOG "$D/jtkey_daemon.log"

proc plog {m} {
    global LOG
    catch {
        set fh [open $LOG a]
        puts $fh "[clock format [clock seconds] -format %H:%M:%S] $m"
        close $fh
    }
    catch {puts $m}
    catch {flush stdout}
}

catch {file delete $LOG}
plog "START [info script]"

connect
after 1500
set tr [targets -set -nocase -filter {name =~ "APU"}]
plog "TARGET_SET $tr"
catch {plog "REG0=[format 0x%08X [mrd -force -value 0x41200000]]"}

# Force all injected keys LOW at start.  The mailbox file may still hold the
# value of a previous session, which would otherwise suppress the first APPLY
# (the daemon only writes on a change) and leave a key stuck.
catch {
    set c0 [mrd -force -value 0x41200000]
    set w0 [expr {($c0 & ~0x1F0) | 0x100}]
    mwr -force 0x41200000 $w0
    plog "CLEAR reg=[format 0x%08X $w0]"
}

set last ""
if {[file exists $F]} {
    if {[catch {
        set fh [open $F r]
        set last [string trim [read $fh]]
        close $fh
    }]} { set last "" }
}
plog "JTKEY_READY cmd=$F"

set n 0
set loglast ""
while {1} {
    incr n

    # Every ~2 s re-assert the current key state.  This makes the daemon
    # self-healing: after a PL reconfiguration ps_ctrl resets to 0, so bit8
    # (injection enable) is lost and the next key press would be ignored until
    # the mailbox value changes.  The re-assert restores it automatically.
    if {($n % 100) == 0} { set last "" }

    if {[catch {
        if {[file exists $F]} {
            set fh [open $F r]
            set v [string trim [read $fh]]
            close $fh
            # A torn read (the PC truncates the file while we read) yields "",
            # ignore it instead of poisoning $last.
            if {$v ne "" && $v ne $last} {
                set last $v
                if {[string is integer -strict $v]} {
                    set c [mrd -force -value 0x41200000]
                    set w [expr {($c & ~0x1F0) | 0x100 | (($v & 0xF) << 4)}]
                    mwr -force 0x41200000 $w
                    if {$v ne $loglast} {
                        plog "APPLY k=$v reg=[format 0x%08X $w]"
                        set loglast $v
                    }
                } else {
                    plog "SKIP raw=$v"
                }
            }
        }
    } e]} {
        plog "ERR $e"
    }
    if {($n % 2400) == 0} { plog "ALIVE n=$n" }
    after 20
}
