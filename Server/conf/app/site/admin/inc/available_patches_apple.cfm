<!DOCTYPE HTML PUBLIC "-//W3C//DTD HTML 4.01 Transitional//EN" "http://www.w3.org/TR/html4/loose.dtd">

<script type="text/javascript" src="/admin/js/jquery-latest.js"></script>
<script type="text/javascript" src="/admin/js/jquery-ui-latest.js"></script>
<link rel="stylesheet" type="text/css" media="screen" href="/admin/js/ui/Aristo-jQuery-UI-Theme/css/Aristo/Aristo.css" />
<link rel="stylesheet" type="text/css" media="screen" href="/admin/js/jqGrid/css/ui.jqgrid.css" />
<link rel="stylesheet" type="text/css" href="/admin/js/multiselect/css/ui.multiselect.css" />
<link rel="stylesheet" type="text/css" media="screen" href="/admin/css/mp.css" />
<script type="text/javascript" src="/admin/js/multiselect/ui.multiselect.js"></script>
<script src="/admin/js/jqGrid/js/i18n/grid.locale-en.js" type="text/javascript"></script>
<script src="/admin/js/jqGrid/js/jquery.jqGrid.min.js" type="text/javascript"></script>
<script src="/admin/js/mp-jqgrid-common.js" type="text/javascript"></script>

<script type="text/javascript">	
	function loadContent(param, id, type) 
	{
		$("#dialog").load("/admin/inc/patch_description.cfm?id="+id+"&type="+type);
		$("#dialog").dialog( {
			bgiframe: false, height: 400, width: 600, modal: true 
		} ); 
		$("#dialog").dialog('open');
	}
</script>

<script type="text/javascript">
	$(document).ready(function()
		{
			var lastsel = -1;
			var mygrid = $("#list").jqGrid(
			{
				url:'available_patches_apple.cfc?method=getMPApplePatches', //CFC that will return the users
				datatype: 'json', //We specify that the datatype we will be using will be JSON
				colNames:['', '', 'Patch', 'Version', 'Title', 'Reboot', 'Supported OS', 'Criteria', 'Patch State', 'Release Date', 'akeyReal'],
				colModel :[
				  {name:'akeyE',index:'akeyE', width:18, align:"center", sortable:false, resizable:false, search:false},
				  {name:'akey',index:'akey', width:18, align:"center", sortable:false, resizable:false, search:false},
				  {name:'supatchname', index:'supatchname', width:160, editable:true},
				  {name:'version', index:'version', width:50, sorttype:'float'},
				  {name:'title', index:'title', width:160, align:"left"},
				  {name:'restartaction', index:'restartaction', width:40, align:"center"},
				  {name:'osver_support', index:'osver_support', width:80, align:"left", hidden: true},
				  {name:'hasCriteria', index:'hasCriteria', width:40, align:"center"},
				  {name:'patch_state', index:'patch_state', width:50, align:"left", editable:true, edittype:"select", editoptions:{value:"Production:Production;QA:QA;Create:Create;Disabled:Disabled"}},
				  {name:'postdate', index:'postdate', width:70, align:"center"},
				  {name:'akeyReal', index:'akeyReal', width:70, align:"center", hidden:true}
				],
				altRows:true,
				altclass:'xAltRow',
				pager: jQuery('#pager'), //The div we have specified, tells jqGrid where to put the pager
				rowNum:20, //Number of records we want to show per page
				rowList:[10,20,30,50,100], //Row List, to allow user to select how many rows they want to see per page
				sortorder: "desc", //Default sort order
				sortname: "postdate", //Default sort column
				viewrecords: true, //Shows the nice message on the pager
				imgpath: '/', //Image path for prev/next etc images
				caption: 'Apple Patches', //Grid Name
				height:'auto', //I like auto, so there is no blank space between. Using a fixed height can mean either a scrollbar or a blank space before the pager
				recordtext: "View {0} - {1} of {2} Records",
				pgtext: "Page {0} of {1}",
				pginput:true,
				width:980,
				hidegrid:false,
				editurl:"available_patches_apple.cfc?method=addEditMPApplePatches",//Not used right now.
				toolbar:[false,"top"],//Shows the toolbar at the top. I will decide if I need to put anything in there later.
				//The JSON reader. This defines what the JSON data returned from the CFC should look like
				loadComplete: function()
				{
					var ids = jQuery("#list").getDataIDs();
					for(var i=0;i<ids.length;i++){
						var cl = ids[i];
						var aps = jQuery("#list").getCell(cl,1);
						var suname = jQuery("#list").getCell(cl,2);
						var akey = encodeURI(jQuery("#list").getCell(cl,'akeyReal'));
						info = "<input type='image' style='padding-left:2px;' onclick=loadContent('info','"+akey+"',\'apple\'); src='/admin/images/info_16.png'>";
						edit = "<input type='image' style='padding-left:2px;' onclick=load('apple_patch_builder_wizard_edit.cfm?key="+encodeURI(ids[i])+"&suname="+encodeURI(suname)+"'); src='/admin/images/edit_16.png'>";
						jQuery("#list").setRowData(ids[i],{akeyE:edit,akey:info})
					}
				},
				onSelectRow: function(id)
				{
					if(id && id!==lastsel)
					{
					  lastsel=id;
					}
				},
				ondblClickRow: function(id) 
				{
				    <cfif session.IsAdmin IS true>
					var suPatchNameID = $("#list").getDataIDs().indexOf(lastsel);
					var suPatchNameIDVal = jQuery("#list").getCell(suPatchNameID,2);
					$('#list').editRow(id, true, undefined, function(res) {
					    // res is the response object from the $.ajax call
					    $("#list").trigger("reloadGrid");
					});
					</cfif>
				},
				jsonReader: {
					total: "total",
					page: "page",
					records:"records",
					root: "rows",
					userdata: "userdata",
					cell: "",
					id: "0"
					}
				}
			);

			$("#list").jqGrid('navGrid',"#pager",{edit:false,add:false,del:false},
				{}, // default settings for edit
				{}, // default settings for add
				{}, // delete
				{ sopt:['cn','bw','eq','ne','lt','gt','ew'], closeOnEscape: true, multipleSearch: true, closeAfterSearch: true }, // search options
				{closeOnEscape:true}
				)
			<cfif session.IsAdmin IS true>	
			.navButtonAdd('#pager',{
				caption:"ALL: Create to QA", 
				buttonicon:"ui-icon-gear", 
				title:"Add New Patch",
				onClickButton: function()
				{ 
					$.get( "available_patches_apple.cfc?method=CreateToQA", function( data ) {
				  		$( ".result" ).html( data );
				  		$("#list").trigger("reloadGrid");
					});
				}
			})
			.navButtonAdd('#pager',{
				caption:"ALL: QA to Prod", 
			   	buttonicon:"ui-icon-gear", 
			   	title:"Duplicate Patch",
			   	onClickButton: function(){ 
					$.get( "available_patches_apple.cfc?method=QAToProd", function( data ) {
				  		$( ".result" ).html( data );
				  		$("#list").trigger("reloadGrid");
					});
				}, 
			   	position:"last"
			})
			.navButtonAdd('#pager',{
				caption:"", 
			   	buttonicon:"ui-icon-calculator", 
			   	title:"Choose Columns",
			   	onClickButton: function(){ 
					$("#list").jqGrid('columnChooser');
				}, 
			   	position:"last"
			})
			</cfif>
			;
			$("#list").navButtonAdd("#pager",{caption:"",title:"Toggle Search Toolbar", buttonicon:'ui-icon-pin-s', onClickButton:function(){ mygrid[0].toggleToolbar() } });
			$("#list").jqGrid('filterToolbar',{stringResult: true, searchOnEnter: true, defaultSearch: 'cn'});
			mygrid[0].toggleToolbar();
			
			$(window).bind('resize', function() {
				$("#list").setGridWidth($(window).width()-20);
			}).trigger('resize');
		}
	);
</script>
<div align="center">
<table id="list" cellpadding="0" cellspacing="0" style="font-size:11px;"></table>
<div id="pager" style="text-align:center;font-size:11px;"></div>
</div>
<div id="dialog" title="Detailed Patch Information" style="text-align:left;" class="ui-dialog-titlebar"></div>
