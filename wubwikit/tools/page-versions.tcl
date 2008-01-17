# The next few lines are some temporary stuff because I don't have the
# Wub paths set up properly

lappend auto_path [file dirname [file dirname [file normalize [info script]]]]

package require struct::list 1.6.1
package require Mk4tcl
package require Wikit::Db

# Procedure to display a tuple from a Metakit database for debugging

set dbPath [file normalize [lindex $argv 0]]

mk::file open wdb $dbPath -readonly

puts [join [Wikit::ListPageVersionsDB wdb {*}[lrange $argv 1 end]] \n]