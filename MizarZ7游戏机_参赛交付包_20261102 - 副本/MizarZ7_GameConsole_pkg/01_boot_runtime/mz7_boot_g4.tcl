#=============================================================================
# mz7_boot.tcl  -  JTAG ???g4?????? 4 ?? + PS/2 + OpenMV ???
#=============================================================================
set D D:/FPGAproject/MizarZ7_JTAGboot
set BIT D:/FPGAproject/MizarZ7_JTAGboot/top_ps_g4.bit

proc a9 {} { targets -set -nocase -filter {name =~ "*Cortex-A9*#0"} }
proc hlt {} {
    if {[catch {stop} e]} {
        if {[string match "*Already stopped*" $e]} { return 0 }
        return -code error $e
    }
    return 0
}

connect
after 3000
catch {a9}
catch {rst -processor}
after 2500

set ok 0
for {set i 0} {$i < 6} {incr i} {
    catch {rst -system}
    after 5000
    catch {a9}
    if {![catch {hlt} e]} { set ok 1; puts "  halt OK ($i)"; break }
    catch {rst -processor}
    after 2500
}
if {!$ok} { puts "FATAL: halt failed"; exit }

catch {targets -set -nocase -filter {name =~ "*Cortex-A9*#1"}}
catch {hlt}
a9
catch {hlt}

source $D/ps7_init_usb.tcl
ps7_init
ps7_post_config

fpga -file $BIT
after 3000

# bit8 = key-injection enable.  bit9 (PS text panel) is left OFF here because
# the 480x96 panel covers the "GAME CONSOLE" title and the first menu bar.
# To switch the panel on later :  mwr -force 0x41200000 [expr {[mrd -force -value 0x41200000] | 0x200}]
mwr -force 0x41200000 [expr {[mrd -force -value 0x41200000] | 0x100}]
puts "CTRL=[format 0x%08X [mrd -force -value 0x41200000]]"
puts "APER_AFTER_PSINIT=[format 0x%08X [mrd -force -value 0xF800012C]]"

mwr -force 0xF8000008 0x0000DF0D
mwr -force 0xF8000910 0x1F
mwr -force 0xF8000004 0x0000767B

dow -data $D/zImage             0x08000000
dow -data $D/system_raw.dtb     0x0A000000
dow -data $D/rootfs_raw.cpio.gz 0x10000000
puts "DOWN_OK"

catch {hlt}
rwr r0 0
rwr r1 0
rwr r2 0x0A000000
rwr pc 0x08000000
con
puts "BOOT_STARTED"

