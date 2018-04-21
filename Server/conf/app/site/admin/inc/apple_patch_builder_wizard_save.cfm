<cfscript>
   function isEmpty(str) {
      if(NOT len(trim(str)))
         return false;
      else
         return true;
      } 
</cfscript>
<!--- This Requires Multiple Database Inserts --->

<!--- Setup Variables that make this entry unique --->
<cfset ts=DateFormat(Now(),"yyyy-mm-dd") & " " & TimeFormat(Now(),"HH:mm:ss") & " ">

<!--- Define form.vars for non required fields --->
<cfparam name="form.patch_severity" default="Low">
<cfparam name="form.patchInstallWeight" default="51">
<cfparam name="form.patch_reboot" default="0">

<!--- Update the Main Record --->
<cftry>
<cfquery name="qInsert1" datasource="#session.dbsource#" result="res">
	Update	apple_patches_mp_additions
      Set
      severity = <cfqueryparam value="#form.patch_severity#">,
			patch_install_weight = <cfqueryparam value="#form.patchInstallWeight#">,
			patch_reboot = <cfqueryparam value="#form.patch_reboot#">,
      user_install = <cfqueryparam value="#form.user_install#">
      Where 
      supatchname = <cfqueryparam value="#form.akey#">
</cfquery>
<cfcatch type="any">
	<!--- The message to display. --->
       <h3><b>Error</b></h3>
       <cfoutput>
           <p>#cfcatch.message#</p>
           <p>Caught an exception, type = #CFCATCH.TYPE#</p>
           <p>The contents of the tag stack are:</p>
           <cfdump var="#cfcatch.tagcontext#">
		<cfabort>
       </cfoutput>
</cfcatch>
</cftry>
<!--- Insert the patch criteria --->
<cftry>
<cfquery name="qInsert2RM" datasource="#session.dbsource#">
    Delete from mp_apple_patch_criteria
    Where puuid = <cfqueryparam value="#form.akey#">
</cfquery>
<cfcatch type="any">
	<!--- The message to display. --->
       <h3><b>Error</b></h3>
       <cfoutput>
           <p>#cfcatch.message#</p>
           <p>Caught an exception, type = #CFCATCH.TYPE#</p>
           <p>The contents of the tag stack are:</p>
           <cfdump var="#cfcatch.tagcontext#">
		<cfabort>
       </cfoutput>
</cfcatch>
</cftry>
<CFLOOP INDEX="TheField" list="#Form.FieldNames#">
	<cfif TheField Contains "REQPATCHCRITERIA_">
    	<cfset nid = ListGetAt(TheField,2,"_")>
        <cfset ntitle = ListGetAt(TheField,1,"_")>
        <cfset order = #Evaluate("REQPATCHCRITERIAORDER_"&nid)#>
        <cftry>
        <cfquery name="qInsert2" datasource="#session.dbsource#">
            Insert Into mp_apple_patch_criteria (
                puuid, supatchname, type, type_action, type_data, type_order
            )
            Values (
                <cfqueryparam value="#form.akey#">, 
				<cfqueryparam value="#form.supatchname#">, 
				<cfqueryparam value="#Evaluate("TYPE_"&nid)#">, 
				<cfqueryparam value="#Evaluate("TYPE_ACTION"&nid)#">, 
				<cfqueryparam value="#Evaluate(ntitle&"_"&nid)#" cfsqltype="CF_SQL_LONGVARCHAR">, 
				<cfqueryparam value="#order#">
            )
        </cfquery>
		<cfcatch type="any">
			<!--- The message to display. --->
		       <h3><b>Error</b></h3>
		       <cfoutput>
		           <p>#cfcatch.message#</p>
		           <p>Caught an exception, type = #CFCATCH.TYPE#</p>
		           <p>The contents of the tag stack are:</p>
		           <cfdump var="#cfcatch.tagcontext#">
				<cfabort>
		       </cfoutput>
		</cfcatch>
		</cftry>
	</cfif>	
</CFLOOP>
<cflocation url="#session.cflocFix#/admin/inc/available_patches_apple.cfm">