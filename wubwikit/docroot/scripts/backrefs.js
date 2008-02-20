/***********************************************
 * Dynamic Ajax Content- © Dynamic Drive DHTML code library (www.dynamicdrive.com)
 * This notice MUST stay intact for legal use
 * Visit Dynamic Drive at http://www.dynamicdrive.com/ for full source code
 * Based on functions taken from Dynamic Ajax Content:
 *    ajaxpage
 *    loadpage
 ***********************************************/
    
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

function loadpage(page_request, containerid){
    if (page_request.readyState == 4 && (page_request.status==200 || window.location.href.indexOf("http")==-1)) {
	if (page_request.responseText.length) {
	    document.getElementById(containerid).innerHTML = page_request.responseText;
	}
    }
}

function getBackRefs(page,containerid)
{
    ajaxpage("/_ref/" + page + "?A=1", "", containerid)
}

function previewPage(page)
{
    document.getElementById("previewarea_pre").innerHTML = "<hr><button type='button' id='previewbutton' onclick='clearPreview();'>Hide preview</button>";
    var txt = document.getElementById("editarea").value;
    ajaxpage("/_preview/" + page, "O="+URLencode(txt), "previewarea");
    return false;
}

function clearPreview()
{
    document.getElementById("previewarea_pre").innerHTML = "";
    document.getElementById("previewarea").innerHTML = "";
    return false;
}

function editHelp()
{
    document.getElementById('helptext').style.display='inline';
    var txt = document.getElementById("editarea").rows=30;
    return false;
}

function hideEditHelp()
{
    document.getElementById('helptext').style.display='none';
    var txt = document.getElementById("editarea").rows=40;
    return false;
}
