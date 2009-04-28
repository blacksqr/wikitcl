function before_selection_after(txtareaid, before_markup, after_markup, defvalue){

    var useragent = navigator.userAgent.toLowerCase();
    var is_gecko = useragent.indexOf('gecko')!=-1;

    var txtarea = document.getElementById(txtareaid);
    if (!is_gecko) {
	var within = document.selection.createRange().text;
	if (within.length == 0)
	    within = defvalue;
	txtarea.focus();
	document.selection.createRange().text = before_markup + within + after_markup;
    } else {
	var sel_start = txtarea.selectionStart;
	var sel_end = txtarea.selectionEnd;
	var before = txtarea.value.substring(0, sel_start);
	var within = txtarea.value.substring(sel_start, sel_end);
	var scroll_pos = txtarea.scrollTop;
	if (within.length == 0)
	    within = defvalue;
	var after  = txtarea.value.substring(sel_end);
	txtarea.value = before + before_markup + within + after_markup + after;
	txtarea.selectionStart = sel_start + before_markup.length;
	txtarea.selectionEnd = sel_start + before_markup.length + within.length;
	txtarea.focus();
	txtarea.scrollTop = scroll_pos;
    }
}

function surround_selection(txtareaid, markup, defvalue){
    before_selection_after(txtareaid, markup, markup, defvalue);
}

function insert_at_selection(txtareaid, markup){
    before_selection_after(txtareaid, markup, "", "");
}

function bold(txtareaid)     { surround_selection(txtareaid, "'''",  "bold text"); return false; }
function italic(txtareaid)   { surround_selection(txtareaid, "''",   "italic text"); return false; }
function teletype(txtareaid) { surround_selection(txtareaid, "`",    "teletype text"); return false; }

function heading1(txtareaid) { before_selection_after(txtareaid, "\n**",   "**\n",   "your heading1"); return false; }
function heading2(txtareaid) { before_selection_after(txtareaid, "\n***" , "***\n",  "your heading2"); return false; }
function heading3(txtareaid) { before_selection_after(txtareaid, "\n****", "****\n", "your heading3"); return false; }

function hruler(txtareaid)   { insert_at_selection(txtareaid, "\n----\n"); return false; }

function list_bullets(txtareaid) { before_selection_after(txtareaid, "\n   * ",  "\n", "your bullet item"); return false; }
function list_numbers(txtareaid) { before_selection_after(txtareaid, "\n   1. ", "\n", "your numbered item"); return false; }

function align_center(txtareaid) { surround_selection(txtareaid, "\n!!!!!!\n", "your centered text"); return false; }

function wiki_link(txtareaid) { before_selection_after(txtareaid, "[", "]", "your wiki page name"); return false; return false; }
function url_link(txtareaid)  { insert_at_selection(txtareaid, "http://here.com/what.html%|%link name%|%"); return false; }
function img_link(txtareaid)  { insert_at_selection(txtareaid, "[http://here.com/photo.gif|png|jpg]"); return false; }

function code(txtareaid)  { surround_selection(txtareaid, "\n======\n", "your script"); return false; }

function table(txtareaid)  { insert_at_selection(txtareaid, "\n%|header|row|%\n&|data|row|&\n&|data|row|&\n&|data|row|&\n"); return false; }
