package require sqlite3 3.6.19
package require tdbc::sqlite3

namespace eval ::tcl::dict {
    proc get? {dict args} {
	if {[dict exists $dict {*}$args]} {
	    return [dict get $dict {*}$args]
	} else {
	    return {}
	}
    }
    namespace ensemble configure dict -map [linsert [namespace ensemble configure dict -map] end get? ::tcl::dict::get?]
}

proc Search {db key long date max} {

    set fields name
    set stmttxt "SELECT a.id, a.name, a.date, a.type FROM pages a, pages_content b WHERE a.id = b.id AND length(a.name) > 0 AND length(b.content) > 1"
    set stmtimg "SELECT a.id, a.name, a.date, a.type FROM pages a, pages_binary b WHERE a.id = b.id"
    if {$long} {
	foreach k [split $key " "] {
	    append stmttxt " AND (lower(a.name) GLOB lower(\"*$k*\") OR lower(b.content) GLOB lower(\"*$k*\"))"
	    append stmtimg " AND lower(a.name) GLOB lower(\"*$k*\")"
	}
    } else {
	foreach k [split $key " "] {
	    append stmttxt " AND lower(a.name) GLOB lower(\"*$k*\")"
	    append stmtimg " AND lower(a.name) GLOB lower(\"*$k*\")"
	}
    }
    if {$date > 0} {
	append stmttxt " AND a.date >= $date"
	append stmtimg " AND a.date >= $date"
    } else {
	append stmttxt " AND a.date > 0"
	append stmtimg " AND a.date > 0"
    }
    append stmttxt " ORDER BY a.date DESC"
    append stmtimg " ORDER BY a.date DESC"

    set results {}
    set n 0
    $db foreach -as dicts d $stmttxt {
	lappend results [list id [dict get $d id] name [dict get $d name] date [dict get $d date] type [dict get? $d type]]
	incr n
	if {$n >= $max} {
	    break
	}
    }

    set n 0
    $db foreach -as dicts d $stmtimg {
	lappend results [list id [dict get $d id] name [dict get $d name] date [dict get $d date] type [dict get? $d type]]
	incr n
	if {$n >= $max} {
	    break
	}
    }

    return [lrange [lsort -integer -decreasing -index 5 $results] 0 [expr {$max-1}]]
}

lassign $argv dbfnm key date max
tdbc::sqlite3::connection create db $dbfnm
set long [regexp {^(.*)\*+$} $key x key]	;# trim trailing *
puts [Search db $key $long $date $max]
db close

exit 0
