# Manually created, package setup

package ifneeded WikitWub 1.0 [list source [file join $dir WikitWub.tcl]]
package ifneeded WikitDb 1.0 [list source [file join $dir WikitDb.tcl]]
package ifneeded WikitRss 1.0 [list source [file join $dir WikitRss.tcl]]

package ifneeded Wikit 1.1 [list source [file join $dir .. wikit wikit.tcl]]

package ifneeded Wikit::Format 1.1 [list source [file join $dir .. wikit format.tcl]]
