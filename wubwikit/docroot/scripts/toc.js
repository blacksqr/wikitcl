
function checkTOC()
{
    // Hide help on edit page
    try {
        document.getElementById('helptext').style.display = 'none';
	document.getElementById("editarea").rows=35;
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
    document.getElementById("editarea").rows=30;
    return false;
}

function hideEditHelp()
{
    document.getElementById('helptext').style.display='none';
    document.getElementById("editarea").rows=35;
    return false;
}
