function clearSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'black';
	txt.value = '';
}

function setSearch() {
	var txt = document.getElementById('searchtxt');
	txt.style.color = 'gray';
	if (txt.value == '') {
		txt.value = 'Search titles';
	}
}

function clearGoogle() {
	var txt = document.getElementById('googletxt');
	txt.style.color = 'black';
	txt.value = '';
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
    document.getElementById("page_toc").innerHTML = "";
    document.title = "Search";
    document.getElementById("title").innerHTML = "Search";
    document.getElementById("updated").innerHTML = "";
    document.getElementById("wiki_menu").innerHTML = "<ul id='menu'><li><a href='http://wiki.tcl.tk'>Home</a></li><li><a href='/4'>Recent changes</a></li><li><a href='/3'>Help</a></li></ul>";
    document.getElementById("footer").innerHTML = "<a href='http://wiki.tcl.tk'>Home</a> &bull; <a href='/4'>Recent changes</a> &bull; <a href='/3'>Help</a> &bull; <a href='/2'>Search</a>";
    document.getElementById("content").innerHTML = "<div id='branding'>Powered by google</div>";
    GSearch.getBranding(document.getElementById("branding"));
    document.getElementById("content").innerHTML += "<p><div id='searchprogress'>Searching for &quot;<b>" + query + "</b>&quot;...</div></p>";
    this.siteSearch.execute(query);
}

App.prototype.OnSearchComplete = function() {
    var eos = 0;
    if (this.siteSearch.results && this.siteSearch.results.length > 0) {
	document.getElementById("content").innerHTML += "<ul>";
	for (var i = 0; i < this.siteSearch.results.length; i++) {
            var result = this.siteSearch.results[i];
	    try {
		var h = "<li class='result'><a href='" + result.url + "'>" + result.title + "</a><p class='result'>" + result.content + "</p></li>";
		document.getElementById("content").innerHTML += h;
		this.resultCount++;
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
	    document.getElementById("searchprogress").innerHTML = "Search results for &quot;<b>" + this.query + "</b>&quot;:";
	    document.getElementById("content").innerHTML += "<p><a class='googlesearch' target='_blank' href='http://www.google.com/search?q=" + URLencode(googleQuery) + "'>Click here to see all matches on Google Web Search</a></p>";
	}
	else {
	    document.getElementById("searchprogress").innerHTML = "No search results for &quot;<b>" + this.query + "</b>&quot;.";
	}
    }
}

function googleQuery() {
    var app = new App(document.getElementById("googletxt").value);
    return false;
}
