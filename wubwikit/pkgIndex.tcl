# Manually created, package setup

package ifneeded WikitWub 1.0 [list source [file join $dir WikitWub.tcl]]
package ifneeded WikitRss 1.0 [list source [file join $dir WikitRss.tcl]]

package ifneeded Wikit 1.1 [list source [file join $dir .. wikit wikit.tcl]]

package ifneeded Wikit::Format 1.1 [list source [file join $dir .. wikit format.tcl]]
package ifneeded Wikit::Gui 1.1 [list source [file join $dir .. wikit gui.tcl]]

package ifneeded Wikit::Db 1.2 [list source [file join $dir .. wikit db.tcl]]
package ifneeded Wikit::Cache 1.0 [list source [file join $dir .. wikit cache.tcl]]
package ifneeded Wikit::Image 1.0 [list source [file join $dir .. wikit image.tcl]]
package ifneeded Wikit::Lock 1.0 [list source [file join $dir .. wikit lock.tcl]]
package ifneeded Wikit::Search 1.0 [list source [file join $dir .. wikit search.tcl]]
package ifneeded Wikit::Utils 1.0 [list source [file join $dir .. wikit utils.tcl]]
