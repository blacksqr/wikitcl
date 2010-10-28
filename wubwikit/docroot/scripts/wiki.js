/*
 * common.js
 */

/**
 * addEvent written by Dean Edwards, 2005
 * with input from Tino Zijdel
 *
 * http://dean.edwards.name/weblog/2005/10/add-event/
 **/
function addEvent(element, type, handler) {
	// assign each event handler a unique ID
	if (!handler.$$guid) handler.$$guid = addEvent.guid++;
	// create a hash table of event types for the element
	if (!element.events) element.events = {};
	// create a hash table of event handlers for each element/event pair
	var handlers = element.events[type];
	if (!handlers) {
		handlers = element.events[type] = {};
		// store the existing event handler (if there is one)
		if (element["on" + type]) {
			handlers[0] = element["on" + type];
		}
	}
	// store the event handler in the hash table
	handlers[handler.$$guid] = handler;
	// assign a global event handler to do all the work
	element["on" + type] = handleEvent;
};
// a counter used to create unique IDs
addEvent.guid = 1;

function removeEvent(element, type, handler) {
	// delete the event handler from the hash table
	if (element.events && element.events[type]) {
		delete element.events[type][handler.$$guid];
	}
};

function handleEvent(event) {
	var returnValue = true;
	// grab the event object (IE uses a global event object)
	event = event || fixEvent(window.event);
	// get a reference to the hash table of event handlers
	var handlers = this.events[event.type];
	// execute each event handler
	for (var i in handlers) {
		this.$$handleEvent = handlers[i];
		if (this.$$handleEvent(event) === false) {
			returnValue = false;
		}
	}
	return returnValue;
};

function fixEvent(event) {
	// add W3C standard event methods
	event.preventDefault = fixEvent.preventDefault;
	event.stopPropagation = fixEvent.stopPropagation;
	return event;
};
fixEvent.preventDefault = function() {
	this.returnValue = false;
};
fixEvent.stopPropagation = function() {
	this.cancelBubble = true;
};

// end from Dean Edwards


/**
 * Creates an Element for insertion into the DOM tree.
 * From http://simon.incutio.com/archive/2003/06/15/javascriptWithXML
 *
 * @param element the element type to be created.
 *				e.g. ul (no angle brackets)
 **/
function createElement(element) {
	if (typeof document.createElementNS != 'undefined') {
		return document.createElementNS('http://www.w3.org/1999/xhtml', element);
	}
	if (typeof document.createElement != 'undefined') {
		return document.createElement(element);
	}
	return false;
}

/**
 * "targ" is the element which caused this function to be called
 * from http://www.quirksmode.org/js/events_properties.html
 **/
function getEventTarget(e) {
	var targ;
	if (!e) {
		e = window.event;
	}
	if (e.target) {
		targ = e.target;
	} else if (e.srcElement) {
		targ = e.srcElement;
	}
	if (targ.nodeType == 3) { // defeat Safari bug
		targ = targ.parentNode;
	}

	return targ;
}

/*
 * css.js
 */

/**
 * Written by Neil Crosby. 
 * http://www.workingwith.me.uk/
 *
 * Use this wherever you want, but please keep this comment at the top of this file.
 *
 * Copyright (c) 2006 Neil Crosby
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy 
 * of this software and associated documentation files (the "Software"), to deal 
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
 * copies of the Software, and to permit persons to whom the Software is 
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in 
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
 * SOFTWARE.
 **/
var css = {
	/**
	 * Returns an array containing references to all elements
	 * of a given tag type within a certain node which have a given class
	 *
	 * @param node		the node to start from 
	 *					(e.g. document, 
	 *						  getElementById('whateverStartpointYouWant')
	 *					)
	 * @param searchClass the class we're wanting
	 *					(e.g. 'some_class')
	 * @param tag		 the tag that the found elements are allowed to be
	 *					(e.g. '*', 'div', 'li')
	 **/
	getElementsByClass : function(node, searchClass, tag) {
		var classElements = new Array();
		var els = node.getElementsByTagName(tag);
		var elsLen = els.length;
		var pattern = new RegExp("(^|\\s)"+searchClass+"(\\s|$)");
		
		
		for (var i = 0, j = 0; i < elsLen; i++) {
			if (this.elementHasClass(els[i], searchClass) ) {
				classElements[j] = els[i];
				j++;
			}
		}
		return classElements;
	},


	/**
	 * PRIVATE.  Returns an array containing all the classes applied to this
	 * element.
	 *
	 * Used internally by elementHasClass(), addClassToElement() and 
	 * removeClassFromElement().
	 **/
	privateGetClassArray: function(el) {
		return el.className.split(' '); 
	},

	/**
	 * PRIVATE.  Creates a string from an array of class names which can be used 
	 * by the className function.
	 *
	 * Used internally by addClassToElement().
	 **/
	privateCreateClassString: function(classArray) {
		return classArray.join(' ');
	},

	/**
	 * Returns true if the given element has been assigned the given class.
	 **/
	elementHasClass: function(el, classString) {
		if (!el) {
			return false;
		}
		
		var regex = new RegExp('\\b'+classString+'\\b');
		if (el.className.match(regex)) {
			return true;
		}

		return false;
	},

	/**
	 * Adds classString to the classes assigned to the element with id equal to
	 * idString.
	 **/
	addClassToId: function(idString, classString) {
		this.addClassToElement(document.getElementById(idString), classString);
	},

	/**
	 * Adds classString to the classes assigned to the given element.
	 * If the element already has the class which was to be added, then
	 * it is not added again.
	 **/
	addClassToElement: function(el, classString) {
		var classArray = this.privateGetClassArray(el);

		if (this.elementHasClass(el, classString)) {
			return; // already has element so don't need to add it
		}

		classArray.push(classString);

		el.className = this.privateCreateClassString(classArray);
	},

	/**
	 * Removes the given classString from the list of classes assigned to the
	 * element with id equal to idString
	 **/
	removeClassFromId: function(idString, classString) {
		this.removeClassFromElement(document.getElementById(idString), classString);
	},

	/**
	 * Removes the given classString from the list of classes assigned to the
	 * given element.  If the element has the same class assigned to it twice, 
	 * then only the first instance of that class is removed.
	 **/
	removeClassFromElement: function(el, classString) {
		var classArray = this.privateGetClassArray(el);

		for (x in classArray) {
			if (classString == classArray[x]) {
				classArray[x] = '';
				break;
			}
		}

		el.className = this.privateCreateClassString(classArray);
	}
}

/*
 * standardista-table-sorting.js
 */

/**
 * Written by Neil Crosby. 
 * http://www.workingwith.me.uk/articles/scripting/standardista_table_sorting
 *
 * This module is based on Stuart Langridge's "sorttable" code.  Specifically, 
 * the determineSortFunction, sortCaseInsensitive, sortDate, sortNumeric, and
 * sortCurrency functions are heavily based on his code.  This module would not
 * have been possible without Stuart's earlier outstanding work.
 *
 * Use this wherever you want, but please keep this comment at the top of this file.
 *
 * Copyright (c) 2006 Neil Crosby
 *
 * Permission is hereby granted, free of charge, to any person obtaining a copy 
 * of this software and associated documentation files (the "Software"), to deal 
 * in the Software without restriction, including without limitation the rights
 * to use, copy, modify, merge, publish, distribute, sublicense, and/or sell 
 * copies of the Software, and to permit persons to whom the Software is 
 * furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in 
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR 
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, 
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE 
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER 
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, 
 * OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE 
 * SOFTWARE.
 **/
var standardistaTableSorting = {

	that: false,
	isOdd: false,

	sortColumnIndex : -1,
	lastAssignedId : 0,
	newRows: -1,
	lastSortedTable: -1,

	/**
	 * Initialises the Standardista Table Sorting module
	 **/
	init : function() {
		// first, check whether this web browser is capable of running this script
		if (!document.getElementsByTagName) {
			return;
		}
		
		this.that = this;
		
		this.run();
		
	},
	
	/**
	 * Runs over each table in the document, making it sortable if it has a class
	 * assigned named "sortable" and an id assigned.
	 **/
	run : function() {
		var tables = document.getElementsByTagName("table");
		
		for (var i=0; i < tables.length; i++) {
			var thisTable = tables[i];
			
			if (css.elementHasClass(thisTable, 'sortable')) {
				this.makeSortable(thisTable);
			}
		}
	},
	
	/**
	 * Makes the given table sortable.
	 **/
	makeSortable : function(table) {
	
		// first, check if the table has an id.  if it doesn't, give it one
		if (!table.id) {
			table.id = 'sortableTable'+this.lastAssignedId++;
		}
		
		// if this table does not have a thead, we don't want to know about it
		if (!table.tHead || !table.tHead.rows || 0 == table.tHead.rows.length) {
			return;
		}
		
		// we'll assume that the last row of headings in the thead is the row that 
		// wants to become clickable
		var row = table.tHead.rows[table.tHead.rows.length - 1];
		
		for (var i=0; i < row.cells.length; i++) {
		
			// create a link with an onClick event which will 
			// control the sorting of the table
			var linkEl = createElement('a');
			linkEl.href = '#';
			linkEl.onclick = this.headingClicked;
			linkEl.setAttribute('columnId', i);
			linkEl.title = 'Click to sort';
			
			// move the current contents of the cell that we're 
			// hyperlinking into the hyperlink
			var innerEls = row.cells[i].childNodes;
			for (var j = 0; j < innerEls.length; j++) {
				linkEl.appendChild(innerEls[j]);
			}
			
			// and finally add the new link back into the cell
			row.cells[i].appendChild(linkEl);

			var spanEl = createElement('span');
			spanEl.className = 'tableSortArrow';
			spanEl.appendChild(document.createTextNode('\u00A0\u00A0'));
			row.cells[i].appendChild(spanEl);

		}
	
		if (css.elementHasClass(table, 'autostripe')) {
			this.isOdd = false;
			var rows = table.tBodies[0].rows;
		
			// We appendChild rows that already exist to the tbody, so it moves them rather than creating new ones
			for (var i=0;i<rows.length;i++) { 
				this.doStripe(rows[i]);
			}
		}
	},
	
	headingClicked: function(e) {
		
		var that = standardistaTableSorting.that;
		
		// linkEl is the hyperlink that was clicked on which caused
		// this method to be called
		var linkEl = getEventTarget(e);
		
		// directly outside it is a td, tr, thead and table
		var td     = linkEl.parentNode;
		var tr     = td.parentNode;
		var thead  = tr.parentNode;
		var table  = thead.parentNode;
		
		// if the table we're looking at doesn't have any rows
		// (or only has one) then there's no point trying to sort it
		if (!table.tBodies || table.tBodies[0].rows.length <= 1) {
			return false;
		}

		// the column we want is indicated by td.cellIndex
		var column = linkEl.getAttribute('columnId') || td.cellIndex;
		//var column = td.cellIndex;
		
		// find out what the current sort order of this column is
		var arrows = css.getElementsByClass(td, 'tableSortArrow', 'span');
		var previousSortOrder = '';
		if (arrows.length > 0) {
			previousSortOrder = arrows[0].getAttribute('sortOrder');
		}
		
		// work out how we want to sort this column using the data in the first cell
		// but just getting the first cell is no good if it contains no data
		// so if the first cell just contains white space then we need to track
		// down until we find a cell which does contain some actual data
		var itm = ''
		var rowNum = 0;
		while ('' == itm && rowNum < table.tBodies[0].rows.length) {
			itm = that.getInnerText(table.tBodies[0].rows[rowNum].cells[column]);
			rowNum++;
		}
		var sortfn = that.determineSortFunction(itm);

		// if the last column that was sorted was this one, then all we need to 
		// do is reverse the sorting on this column
		if (table.id == that.lastSortedTable && column == that.sortColumnIndex) {
			newRows = that.newRows;
			newRows.reverse();
		// otherwise, we have to do the full sort
		} else {
			that.sortColumnIndex = column;
			var newRows = new Array();

			for (var j = 0; j < table.tBodies[0].rows.length; j++) { 
				newRows[j] = table.tBodies[0].rows[j]; 
			}

			newRows.sort(sortfn);
		}

		that.moveRows(table, newRows);
		that.newRows = newRows;
		that.lastSortedTable = table.id;
		
		// now, give the user some feedback about which way the column is sorted
		
		// first, get rid of any arrows in any heading cells
		var arrows = css.getElementsByClass(tr, 'tableSortArrow', 'span');
		for (var j = 0; j < arrows.length; j++) {
			var arrowParent = arrows[j].parentNode;
			arrowParent.removeChild(arrows[j]);

			if (arrowParent != td) {
				spanEl = createElement('span');
				spanEl.className = 'tableSortArrow';
				spanEl.appendChild(document.createTextNode('\u00A0\u00A0'));
				arrowParent.appendChild(spanEl);
			}
		}
		
		// now, add back in some feedback 
		var spanEl = createElement('span');
		spanEl.className = 'tableSortArrow';
		if (null == previousSortOrder || '' == previousSortOrder || 'DESC' == previousSortOrder) {
			spanEl.appendChild(document.createTextNode(' \u2191'));
			spanEl.setAttribute('sortOrder', 'ASC');
		} else {
			spanEl.appendChild(document.createTextNode(' \u2193'));
			spanEl.setAttribute('sortOrder', 'DESC');
		}
		
		td.appendChild(spanEl);
		
		return false;
	},

	getInnerText : function(el) {
		
		if ('string' == typeof el || 'undefined' == typeof el) {
			return el;
		}
		
		if (el.innerText) {
			return el.innerText;  // Not needed but it is faster
		}

		var str = el.getAttribute('standardistaTableSortingInnerText');
		if (null != str && '' != str) {
			return str;
		}
		str = '';

		var cs = el.childNodes;
		var l = cs.length;
		for (var i = 0; i < l; i++) {
			// 'if' is considerably quicker than a 'switch' statement, 
			// in Internet Explorer which translates up to a good time 
			// reduction since this is a very often called recursive function
			if (1 == cs[i].nodeType) { // ELEMENT NODE
				str += this.getInnerText(cs[i]);
				break;
			} else if (3 == cs[i].nodeType) { //TEXT_NODE
				str += cs[i].nodeValue;
				break;
			}
		}
		
		// set the innertext for this element directly on the element
		// so that it can be retrieved early next time the innertext
		// is requested
		el.setAttribute('standardistaTableSortingInnerText', str);
		
		return str;
	},

	determineSortFunction : function(itm) {
		
		var sortfn = this.sortCaseInsensitive;
		
		if (itm.match(/^\d\d[\/-]\d\d[\/-]\d\d\d\d$/)) {
			sortfn = this.sortDate;
		}
		if (itm.match(/^\d\d[\/-]\d\d[\/-]\d\d$/)) {
			sortfn = this.sortDate;
		}
		if (itm.match(/^[£$]/)) {
			sortfn = this.sortCurrency;
		}
		if (itm.match(/^\d?\.?\d+$/)) {
			sortfn = this.sortNumeric;
		}
		if (itm.match(/^[+-]?\d*\.?\d+([eE]-?\d+)?$/)) {
			sortfn = this.sortNumeric;
		}
    		if (itm.match(/^([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])\.([01]?\d\d?|2[0-4]\d|25[0-5])$/)) {
        		sortfn = this.sortIP;
   		}

		return sortfn;
	},
	
	sortCaseInsensitive : function(a, b) {
		var that = standardistaTableSorting.that;
		
		var aa = that.getInnerText(a.cells[that.sortColumnIndex]).toLowerCase();
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]).toLowerCase();
		if (aa==bb) {
			return 0;
		} else if (aa<bb) {
			return -1;
		} else {
			return 1;
		}
	},
	
	sortDate : function(a,b) {
		var that = standardistaTableSorting.that;

		// y2k notes: two digit years less than 50 are treated as 20XX, greater than 50 are treated as 19XX
		var aa = that.getInnerText(a.cells[that.sortColumnIndex]);
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]);
		
		var dt1, dt2, yr = -1;
		
		if (aa.length == 10) {
			dt1 = aa.substr(6,4)+aa.substr(3,2)+aa.substr(0,2);
		} else {
			yr = aa.substr(6,2);
			if (parseInt(yr) < 50) { 
				yr = '20'+yr; 
			} else { 
				yr = '19'+yr; 
			}
			dt1 = yr+aa.substr(3,2)+aa.substr(0,2);
		}
		
		if (bb.length == 10) {
			dt2 = bb.substr(6,4)+bb.substr(3,2)+bb.substr(0,2);
		} else {
			yr = bb.substr(6,2);
			if (parseInt(yr) < 50) { 
				yr = '20'+yr; 
			} else { 
				yr = '19'+yr; 
			}
			dt2 = yr+bb.substr(3,2)+bb.substr(0,2);
		}
		
		if (dt1==dt2) {
			return 0;
		} else if (dt1<dt2) {
			return -1;
		}
		return 1;
	},

	sortCurrency : function(a,b) { 
		var that = standardistaTableSorting.that;

		var aa = that.getInnerText(a.cells[that.sortColumnIndex]).replace(/[^0-9.]/g,'');
		var bb = that.getInnerText(b.cells[that.sortColumnIndex]).replace(/[^0-9.]/g,'');
		return parseFloat(aa) - parseFloat(bb);
	},

	sortNumeric : function(a,b) { 
		var that = standardistaTableSorting.that;

		var aa = parseFloat(that.getInnerText(a.cells[that.sortColumnIndex]));
		if (isNaN(aa)) { 
			aa = 0;
		}
		var bb = parseFloat(that.getInnerText(b.cells[that.sortColumnIndex])); 
		if (isNaN(bb)) { 
			bb = 0;
		}
		return aa-bb;
	},

	makeStandardIPAddress : function(val) {
		var vals = val.split('.');

		for (x in vals) {
			val = vals[x];

			while (3 > val.length) {
				val = '0'+val;
			}
			vals[x] = val;
		}

		val = vals.join('.');

		return val;
	},

	sortIP : function(a,b) { 
		var that = standardistaTableSorting.that;

		var aa = that.makeStandardIPAddress(that.getInnerText(a.cells[that.sortColumnIndex]).toLowerCase());
		var bb = that.makeStandardIPAddress(that.getInnerText(b.cells[that.sortColumnIndex]).toLowerCase());
		if (aa==bb) {
			return 0;
		} else if (aa<bb) {
			return -1;
		} else {
			return 1;
		}
	},

	moveRows : function(table, newRows) {
		this.isOdd = false;

		// We appendChild rows that already exist to the tbody, so it moves them rather than creating new ones
		for (var i=0;i<newRows.length;i++) { 
			var rowItem = newRows[i];

			this.doStripe(rowItem);

			table.tBodies[0].appendChild(rowItem); 
		}
	},
	
	doStripe : function(rowItem) {
		if (this.isOdd) {
			css.addClassToElement(rowItem, 'odd');
		} else {
			css.removeClassFromElement(rowItem, 'odd');
		}
		
		this.isOdd = !this.isOdd;
	}

}

function standardistaTableSortingInit() {
	standardistaTableSorting.init();
}

addEvent(window, 'load', standardistaTableSortingInit)

/*
 * search.js
 */

function clearSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'black';
	if (txt.value == 'Search in titles') {
	    txt.value = '';
	}
}

function setSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'gray';
	if (txt.value == '') {
		txt.value = 'Search in titles';
	}
}

function clearGoogle() {
	var txt = document.getElementById('googletxt');
	txt.style.color = 'black';
	if (txt.value == 'Search in pages') {
	    txt.value = '';
	}
}

function setGoogle() {
	var txt = document.getElementById('googletxt');
	txt.style.color = 'gray';
	if (txt.value == '') {
		txt.value = 'Search in pages';
	}
}

function URLencode(sStr) {
    return escape(sStr)
	.replace(/\+/g, '%2B')
	.replace(/\"/g,'%22')
	.replace(/\'/g, '%27');
}

function App(query) {
    this.query = query;
    this.resultCount = 0;
    this.siteSearch = new GwebSearch();
    this.siteSearch.setUserDefinedLabel("Tcler's wiki");
    this.siteSearch.setUserDefinedClassSuffix("siteSearch");
    this.siteSearch.setSiteRestriction("http://wiki.tcl.tk");
    this.siteSearch.setResultSetSize(GSearch.LARGE_RESULTSET);
    this.siteSearch.setSearchCompleteCallback(this, App.prototype.OnSearchComplete);
    document.getElementById("content").innerHTML = "<p><div id='searchprogress'>Searching for &quot;<b>" + query + "</b>&quot;...</div></p>";
    this.siteSearch.execute(query);
}

App.prototype.OnSearchComplete = function() {
    var eos = 0;
    if (this.siteSearch.results && this.siteSearch.results.length > 0) {
	document.getElementById("content").innerHTML += "<ul>";
	for (var i = 0; i < this.siteSearch.results.length; i++) {
            var result = this.siteSearch.results[i];
	    try {
		var idx = result.url.lastIndexOf("/");
		var page = "";
		if (idx >= 0)
		    page = result.url.substr(idx);
		if (page != "/4") {
		    var h = "<li class='result'><a href='" + result.url + "'>" + result.title + "</a><p class='result'>" + result.content + "</p></li>";
		    document.getElementById("content").innerHTML += h;
		    this.resultCount++;
		}
	    }
	    catch(err) {
	    }
	}	
	document.getElementById("content").innerHTML += "</ul>";
	var cursor = this.siteSearch.cursor;
	if (cursor && cursor.currentPageIndex < cursor.pages.length - 1) {
	    this.siteSearch.gotoPage(cursor.currentPageIndex + 1);
	}
	else
	    eos = 1;
    }
    else
	eos = 1;
    
    if (eos) {
	var googleQuery = this.query + " site:http://wiki.tcl.tk";
	if (this.resultCount > 0) {
	    document.getElementById("searchprogress").innerHTML = "Search results for &quot;<b>" + this.query + "</b>&quot;";
	    document.getElementById("content").innerHTML += "<p><a class='googlesearch' target='_blank' href='http://www.google.com/search?q=" + URLencode(googleQuery) + "'>Click here to see all matches on Google Web Search</a></p>"
	}
	else {
	    document.getElementById("searchprogress").innerHTML = "No search results for &quot;<b>" + this.query + "</b>&quot;";
	}
    }
}

function googleQuery() {
    var app = new App(document.getElementById("googletxt").value);
    return false;
}

/*
 * backrefs.js
 */

/***********************************************
 * Dynamic Ajax Content- © Dynamic Drive DHTML code library (www.dynamicdrive.com)
 * This notice MUST stay intact for legal use
 * Visit Dynamic Drive at http://www.dynamicdrive.com/ for full source code
 * Based on functions taken from Dynamic Ajax Content:
 *    ajaxpage
 *    loadpage
 ***********************************************/

function ajaxpage(url, postData, containerid){
    ajaxpage(url, postData, containerid, 0);
}
    
function ajaxpage(url, postData, containerid){
    var page_request = false
    if (window.XMLHttpRequest) // if Mozilla, Safari etc
        page_request = new XMLHttpRequest()
    else if (window.ActiveXObject){ // if IE
	try {
	    page_request = new ActiveXObject("Msxml2.XMLHTTP")
	} 	
	catch (e){
	    try{
		page_request = new ActiveXObject("Microsoft.XMLHTTP")
	    }
	    catch (e){}
	}
    }
    else
        return false

    page_request.onreadystatechange=function(){
	    loadpage(page_request, containerid)
    }
    if (postData.length) {
	page_request.open('POST', url, true);
	page_request.setRequestHeader('Content-type', "application/xml");
	page_request.setRequestHeader('Content-length', postData.length);
	page_request.send(postData);
    }
    else {
	page_request.open('GET', url, true);
	page_request.send(null);
    }
}

function loadpage(page_request, containerid) {
    if (page_request.readyState == 4 && (page_request.status==200 || window.location.href.indexOf("http")==-1)) {
	if (page_request.responseText.length) {
	    document.getElementById(containerid).innerHTML = page_request.responseText;
	}
    }
}

function getBackRefs(page,containerid)
{
    ajaxpage("/_/ref", "N=" + page + "&A=1", containerid)
}

function getIncluded(page,containerid)
{
    ajaxpage("/_/included", "N=" + page, containerid)
}

/**
*
*  URL encode / decode
*  http://www.webtoolkit.info/
*
**/

var Url = {

    // public method for url encoding
    encode : function (string) {
        return escape(this._utf8_encode(string)).replace(/\+/g, "%2B");
    },

    // public method for url decoding
    decode : function (string) {
        return this._utf8_decode(unescape(string));
    },

    // private method for UTF-8 encoding
    _utf8_encode : function (string) {
        string = string.replace(/\r\n/g,"\n");
        var utftext = "";

        for (var n = 0; n < string.length; n++) {

            var c = string.charCodeAt(n);

            if (c < 128) {
                utftext += String.fromCharCode(c);
            }
            else if((c > 127) && (c < 2048)) {
                utftext += String.fromCharCode((c >> 6) | 192);
                utftext += String.fromCharCode((c & 63) | 128);
            }
            else {
                utftext += String.fromCharCode((c >> 12) | 224);
                utftext += String.fromCharCode(((c >> 6) & 63) | 128);
                utftext += String.fromCharCode((c & 63) | 128);
            }

        }

        return utftext;
    },

    // private method for UTF-8 decoding
    _utf8_decode : function (utftext) {
        var string = "";
        var i = 0;
        var c = c1 = c2 = 0;

        while ( i < utftext.length ) {

            c = utftext.charCodeAt(i);

            if (c < 128) {
                string += String.fromCharCode(c);
                i++;
            }
            else if((c > 191) && (c < 224)) {
                c2 = utftext.charCodeAt(i+1);
                string += String.fromCharCode(((c & 31) << 6) | (c2 & 63));
                i += 2;
            }
            else {
                c2 = utftext.charCodeAt(i+1);
                c3 = utftext.charCodeAt(i+2);
                string += String.fromCharCode(((c & 15) << 12) | ((c2 & 63) << 6) | (c3 & 63));
                i += 3;
            }

        }

        return string;
    }

}

function previewPage(page)
{
    document.getElementById("previewarea_pre").innerHTML = "<hr><b>Preview:</b> <button type='button' id='previewbutton' onclick='clearPreview();'>Hide preview</button>";
    document.getElementById("previewarea_post").innerHTML = "<b>Preview:</b> <button type='button' id='previewbutton' onclick='clearPreview();'>Hide preview</button>";
    var txt = document.getElementById("editarea").value;
    ajaxpage("/_/preview", "N=" + page + "&O="+Url.encode(txt), "previewarea");
    return false;
}

function clearPreview()
{
    document.getElementById("previewarea_pre").innerHTML = "";
    document.getElementById("previewarea").innerHTML = "";
    document.getElementById("previewarea_post").innerHTML = "";
    return false;
}

/*
 * toc.js
 */

function checkTOC()
{
    // Hide help on edit page
    try {
        document.getElementById('helptext').style.display = 'none';
    } catch (e) {}
    try {
	document.getElementById("googletxt").value;
	googleQuery();
    }
    catch (e){}
}

function editHelp()
{
    document.getElementById('helptext').style.display='inline';
    return false;
}

function hideEditHelp()
{
    document.getElementById('helptext').style.display='none';
    return false;
}

function toggleDiscussion(n)
{
    try {
	if (document.getElementById('discussion'+n).style.display =='inline') {
	    document.getElementById('discussion'+n).style.display = 'none';
	    document.getElementById('togglediscussionbutton'+n).innerHTML = 'Show' + document.getElementById('togglediscussionbutton'+n).innerHTML.substring(4);
	}
	else {
	    document.getElementById('discussion'+n).style.display = 'inline';
	    document.getElementById('togglediscussionbutton'+n).innerHTML = 'Hide' +  document.getElementById('togglediscussionbutton'+n).innerHTML.substring(4);
	}
    } catch (e) {}
	return false;
}


/*
 * edit.js
 */

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

function bold(txtareaid)     {
    surround_selection(txtareaid, "'''", "bold text");
    return false;
}
function italic(txtareaid)   {
    surround_selection(txtareaid, "''", "italic text");
    return false;	
}
function teletype(txtareaid) {
    surround_selection(txtareaid, "`", "teletype text");
    return false;
}
function superscript(txtareaid) {
    return false;
}
function subscript(txtareaid) {
    return false;
}

function heading1(txtareaid) {
    before_selection_after(txtareaid, "\n**", "**\n", "your heading1");
    return false;
}
function heading2(txtareaid) {
    before_selection_after(txtareaid, "\n***" , "***\n",  "your heading2");
    return false;
}
function heading3(txtareaid) {
    before_selection_after(txtareaid, "\n****", "****\n", "your heading3");
    return false;
}

function hruler(txtareaid)   {
    insert_at_selection(txtareaid, "\n----\n");
    return false;
}

function list_bullets(txtareaid) {
    before_selection_after(txtareaid, "\n   * ",  "\n", "your bullet item");
    return false;
}
function list_numbers(txtareaid) {
    before_selection_after(txtareaid, "\n   1. ", "\n", "your numbered item");
    return false;
}

function align_center(txtareaid) {
    surround_selection(txtareaid, "\n!!!!!!\n", "your centered text");
    return false;
}

function wiki_link(txtareaid) {
    before_selection_after(txtareaid, "[", "]", "your wiki page name");
    return false;
}
function url_link(txtareaid)  {
    insert_at_selection(txtareaid, "http://here.com/what.html%|%link name%|%");
    return false;
}
function img_link(txtareaid)  {
    insert_at_selection(txtareaid, "[http://here.com/photo.gif|png|jpg]");
    return false;
}

function code(txtareaid)  {
    surround_selection(txtareaid, "\n======\n", "your script");
    return false;
}

function table(txtareaid)  {
    insert_at_selection(txtareaid, "\n%|header|row|%\n&|data|row|&\n&|data|row|&\n&|data|row|&\n");
    return false;
}

/*
 * tooltips.js
 */

// Extended Tooltip Javascript
// copyright 9th August 2002, 3rd July 2005, 24th August 2008
// by Stephen Chapman, Felgall Pty Ltd

// permission is granted to use this javascript provided that the
// below code is not altered

function pw() {
    return window.innerWidth || document.documentElement.clientWidth || document.body.clientWidth;
}

function mouseX(evt) {
    return evt.clientX ? evt.clientX + (document.documentElement.scrollLeft || document.body.scrollLeft) : evt.pageX;
}

function mouseY(evt) {
    return evt.clientY ? evt.clientY + (document.documentElement.scrollTop || document.body.scrollTop) : evt.pageY;
}

function popUp(evt,oi) {
    if (document.getElementById) {
	var wp = pw();
	dm = document.getElementById(oi);
	ds = dm.style;
	st = ds.visibility;
	if (dm.offsetWidth)
	    ew = dm.offsetWidth;
	else if (dm.clip.width)
	    ew = dm.clip.width;
	if (st == "visible" || st == "show") {
	    ds.visibility = "hidden";
	}
	else {
	    tv = mouseY(evt) + 20;
	    lv = mouseX(evt) - (ew/4);
	    if (lv < 2)
		lv = 2;
	    else if (lv + ew > wp)
		lv -= ew/2;
	    lv += 'px';
	    tv += 'px';
	    ds.left = lv;
	    ds.top = tv;
	    ds.visibility = "visible";
	}
    }
}
                  
/*
 * compare versions
 */

function versionCompare(N, W) 
{
    var A = -1;
    var B = -1;
    var i = -1;
    for(i = 0; i < 1000 && (A < 0 || B < 0); i++) {
	try {
	    var p = document.getElementById("historyA"+i);
	    if (p.checked) {
		A = p.value;
	    }
	    p = document.getElementById("historyB"+i);
	    if (p.checked) {
		B = p.value;
	    }
	}
	catch(err) {
	    break
	}
    }
    location.href = "diff?N="+N+"&V="+A+"&D="+B+"&W="+W+"#diff0";
}
