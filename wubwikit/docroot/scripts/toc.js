
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
