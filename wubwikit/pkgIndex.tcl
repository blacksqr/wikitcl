# Manually created, package setup

package ifneeded WikitWub 1.0 [list source [file join $dir WikitWub.tcl]]
package ifneeded WikitWubTemplates 1.0 [list source [file join $dir WikitWubTemplates.tcl]]
package ifneeded WDB_mk 1.0 [list source [file join $dir WDB.tcl]]
package ifneeded WDB_sqlite 1.0 [list source [file join $dir WDB_sqlite.tcl]]
package ifneeded WikitRss 1.0 [list source [file join $dir WikitRss.tcl]]
package ifneeded WFormat 1.1 [list source [file join $dir WFormat.tcl]]
