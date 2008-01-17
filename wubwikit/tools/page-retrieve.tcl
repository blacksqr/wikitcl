# The next few lines are some temporary stuff because I don't have the
# Wub paths set up properly

lappend auto_path [file dirname [file dirname [file normalize [info script]]]]

package require struct::list 1.6.1
package require Mk4tcl
package require Wikit::Db

set dbPath [file normalize [lindex $argv 0]]
set pageNo [lindex $argv 1]
set versionNo [lindex $argv 2]

Wikit::WikiDatabase $dbPath wdb

puts [Wikit::GetPageVersion $pageNo $versionNo wdb]
