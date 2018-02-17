<cfcomponent output="false" extends="jqGrid">

	<cfset this.logName = "available_patches_apple" />

	<cffunction name="getMPApplePatches" access="remote" returnformat="json">
		<cfargument name="page" required="no" default="1" hint="Page user is on">
	    <cfargument name="rows" required="no" default="10" hint="Number of Rows to display per page">
	    <cfargument name="sidx" required="no" default="" hint="Sort Column">
	    <cfargument name="sord" required="no" default="ASC" hint="Sort Order">
	    <cfargument name="nd" required="no" default="0">
	    <cfargument name="_search" required="no" default="false">
	    <cfargument name="filters" required="no" default="">
		
		<cfset var arrUsers = ArrayNew(1)>
		<cfset var strMsg = "">
		<cfset var strMsgType = "Success">
		<cfset var records = "">
		<cfset var blnSearch = Arguments._search>
		<cfset var strSearch = "">	
		
		<cfif Arguments.filters NEQ "" AND blnSearch>
			<cfset stcSearch = DeserializeJSON(Arguments.filters)>
            <cfif isDefined("stcSearch.groupOp")>
            	<cfset strSearch = buildSearch(stcSearch)>
            </cfif>            
        </cfif>
		
		<cftry>
			<cfquery name="selUsers" datasource="#session.dbsource#" result="res">
				select Distinct ap.akey, ap.supatchname, ap.postdate, ap.title, ap.version, ap.restartaction, GROUP_CONCAT(ap.osver_support) as osver_support, apr.patch_state,
				CASE WHEN EXISTS
				( SELECT 1
					FROM mp_apple_patch_criteria apc
					WHERE apc.puuid = ap.supatchname)
				THEN "Yes" ELSE "No"
				END AS hasCriteria
	   			From apple_patches ap
				INNER JOIN apple_patches_mp_additions apr ON ap.supatchname = apr.supatchname
				GROUP BY ap.akey
				<cfif blnSearch AND strSearch NEQ "">
                    #PreserveSingleQuotes(strSearch)#
            	</cfif>
				
				ORDER BY #sidx# #sord#
			</cfquery>
			
            <cfcatch type="any">
				<cfset blnSearch = false>					
				<cfset strMsgType = "Error">
				<cfset strMsg = "There was an issue with the Search. An Error Report has been submitted to Support.">
			</cfcatch>		
		</cftry>
		
		<cfset records = selUsers>
		<cfset start = ((arguments.page-1)*arguments.rows)+1>
		<cfset end = (start-1) + arguments.rows>
		<cfset i = 1>

		<cfloop query="selUsers" startrow="#start#" endrow="#end#">
			<cfset arrUsers[i] = [#supatchname#, #supatchname#, #supatchname#, #version#, #title#, #iif(restartaction EQ "NoRestart",DE("No"),DE("Yes"))#, #osver_support#, #hasCriteria#, #patch_state#, #DateTimeFormat( postdate, "yyyy-MM-dd HH:mm:ss" )#, #akey#]>
			<cfset i = i + 1>			
		</cfloop>

		<cfset totalPages = Ceiling(selUsers.recordcount/arguments.rows)>
		<cfset stcReturn = {total=#totalPages#,page=#Arguments.page#,records=#selUsers.recordcount#,rows=#arrUsers#}>
		<cfreturn stcReturn>
	</cffunction>
  
    <cffunction name="addEditMPApplePatches" access="remote" hint="Add or Edit" returnformat="json" output="no">
		<cfargument name="id" required="no" hint="Field that was editted">
		<cfargument name="patch_state" required="no">
		
		<cfset var strMsg = "">
		<cfset var strMsgType = "Success">
		<cfset var userdata = "">
        
		<cfif oper EQ "edit">
			<cftry>
				<cfquery name="editRecord1" datasource="#session.dbsource#" result="res1">
					UPDATE
						apple_patches
					SET
						supatchname = <cfqueryparam value="#arguments.supatchname#">
					WHERE
						supatchname = <cfqueryparam value="#arguments.id#">
				</cfquery>

				<cfquery name="editRecord2" datasource="#session.dbsource#" result="res2">
					UPDATE
						apple_patches_mp_additions
					SET
						patch_state = <cfqueryparam value="#Arguments.patch_state#">,
						supatchname = <cfqueryparam value="#arguments.supatchname#">
					WHERE
						supatchname = <cfqueryparam value="#arguments.id#">
				</cfquery>
                <cfcatch type="any">			
					<cfset strMsgType = "Error">
					<cfset strMsg = "There was an issue with the Edit. An Error Report has been submitted to Support.">					
				</cfcatch>		
			</cftry>
		<cfelseif oper EQ "add">
			<cfset strMsgType = "Add">
			<cfset strMsg = "Notice, MP add."> 
        <cfelseif oper EQ "del">    
            <cfset strReturn = delMPPatch(Arguments.id)>
            <cfreturn strReturn>
		</cfif>

		<cfset userdata  = {type='#strMsgType#',msg='#strMsg#'}>
		<cfset strReturn = {userdata=#userdata#}>		
		<cfreturn strReturn>
	</cffunction>
	
	<cffunction name="CreateToQA" access="remote" returnformat="json" output="no">
		
		<cfset var strMsg = "">
		<cfset var strMsgType = "Success">
		<cfset var userdata = "">

		<cftry>
			<cfquery name="editRecord" datasource="#session.dbsource#" result="res">
				UPDATE apple_patches_mp_additions
				SET patch_state = "QA"
				WHERE patch_state = "Create"
			</cfquery>
               <cfcatch type="any">			
				<cfset strMsgType = "Error">
				<cfset strMsg = "There was an issue with the Edit. An Error Report has been submitted to Support.">					
			</cfcatch>		
		</cftry>

		<cfset userdata  = {type='#strMsgType#',msg='#strMsg#'}>
		<cfset strReturn = {userdata=#userdata#}>		
		<cfreturn strReturn>
	</cffunction>
	
	<cffunction name="QAToProd" access="remote" returnformat="json" output="no">
		
		<cfset var strMsg = "">
		<cfset var strMsgType = "Success">
		<cfset var userdata = "">

		<cftry>
			<cfquery name="editRecord" datasource="#session.dbsource#" result="res">
				UPDATE apple_patches_mp_additions
				SET patch_state = "Production"
				WHERE patch_state = "QA"
			</cfquery>
               <cfcatch type="any">			
				<cfset strMsgType = "Error">
				<cfset strMsg = "There was an issue with the Edit. An Error Report has been submitted to Support.">					
			</cfcatch>		
		</cftry>

		<cfset userdata  = {type='#strMsgType#',msg='#strMsg#'}>
		<cfset strReturn = {userdata=#userdata#}>		
		<cfreturn strReturn>
	</cffunction>
    
    <cffunction name="delMPPatch" access="private" hint="Delete Selected MP patch" returntype="struct">		
		<cfargument name="id" required="yes" hint="id to delete">
		
		<cfset var strMsg = "">
		<cfset var strMsgType = "Success">
        <cfset var userdata = "">
		
		<cftry>
			<cfset strMsg = "Delete MP patch">
		<cfcatch>
			<!--- Error, return message --->
			<cfset strMsgType = "Error">
			<cfset strMsg = "Error occured when Deleting MP patch. An error report has been submitted to support.">
		</cfcatch>
		</cftry>
		
		<cfset userdata  = {type='#strMsgType#', msg='#strMsg#'}>
		<cfset strReturn = {userdata=#userdata#}>
		
		<cfreturn strReturn>
	</cffunction>
</cfcomponent>	