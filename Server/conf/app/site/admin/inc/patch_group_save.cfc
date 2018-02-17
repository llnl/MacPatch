<cfcomponent>
	
    <cfset this.ds = "mpds">

	<cffunction name="init" returntype="patch_group_save" output="no">
    	<cfargument name="datasource" required="yes">
        <cfset this.ds = arguments.datasource>
		<cfreturn this>
	</cffunction>
    
    <cffunction name="GetPatchGroupPatchesExtended" access="public" returntype="any" output="no">
        <cfargument name="PatchGroupID" required="yes">

        <cftry>
            <cfquery datasource="#this.ds#" name="qGetUpdatesApple">
            	Select mpg.name, mpgp.patch_id, cpfv.type, cpfv.reboot, cpfv.suname, cpfv.size,
				CASE WHEN EXISTS
				( SELECT 1
					FROM mp_apple_patch_criteria v
					WHERE v.puuid = mpgp.patch_id)
				THEN "1" ELSE "0"
				END AS hasCriteria
                From mp_patch_group mpg
                Join mp_patch_group_patches mpgp
                ON mpg.id = mpgp.patch_group_id
                Join combined_patches_view cpfv
                ON mpgp.patch_id = cpfv.id

                Where mpg.id like <cfqueryparam value="#arguments.PatchGroupID#">
                AND cpfv.type = 'Apple'
            </cfquery>
            <cfcatch type="any">
            <cfinvoke component="ws_logger" method="LogEvent">
                <cfinvokeargument name="aEventType" value="Error">
                <cfinvokeargument name="aHost" value="#CGI.REMOTE_HOST#">
                <cfinvokeargument name="aEvent" value="[GetPatchGroupPatches][qGetUpdatesApple]: #cfcatch.Detail# -- #cfcatch.Message#">
            </cfinvoke>
            </cfcatch>
        </cftry>
        <cftry>
            <cfquery datasource="#this.ds#" name="qGetUpdatesThird">
            	Select mpg.name as name, mpgp.patch_id as id, cpfv.type as type, cpfv.reboot as reboot, cpfv.suname as suname, mpp.pkg_hash as hash, mpp.pkg_path as path, mpp.pkg_size as size,
                From mp_patch_group mpg
                Join mp_patch_group_patches mpgp
                ON mpg.id = mpgp.patch_group_id
                Join combined_patches_view cpfv
                ON mpgp.patch_id = cpfv.id
                Join mp_patches mpp
                ON mpp.puuid = mpgp.patch_id

                Where mpg.id like <cfqueryparam value="#arguments.PatchGroupID#">
                AND cpfv.type = 'Third'
            </cfquery>
            <cfcatch type="any">
            <cfinvoke component="ws_logger" method="LogEvent">
                <cfinvokeargument name="aEventType" value="Error">
                <cfinvokeargument name="aHost" value="#CGI.REMOTE_HOST#">
                <cfinvokeargument name="aEvent" value="[GetPatchGroupPatches][qGetUpdatesThird]: #cfcatch.Detail# -- #cfcatch.Message#">
            </cfinvoke>
            </cfcatch>
        </cftry>

        <cfset thirdIDList = ValueList(qGetUpdatesThird.id)>
        <cfset var a_criteria = QueryNew("puuid, supatchname, type, type_order, type_action, type_data")>  />

		<cfsavecontent variable="thePlist">
        <cfprocessingdirective SUPPRESSWHITESPACE="true">
            <?xml version="1.0" encoding="UTF-8"?>
            <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
            <plist version="1.0">
            <dict>
                <key>AppleUpdates</key>
                <array>
                <cfloop query="qGetUpdatesApple"><cfoutput>
					<cfif #Right(Trim(suname),1)# NEQ "-">
					<cfset a_criteria = #GetApplePatchCriteria(patch_id)# />
                    <dict>
						<key>name</key>
                        <string>#Trim(suname)#</string>
						<key>patchid</key>
                        <string>#Trim(patch_id)#</string>
						<key>baseline</key>
                        <string>0</string>
                        <key>hasCriteria</key>
                        <cfif #hasCriteria# EQ "1">
						<true/>
						<key>criteria_pre</key>
						<array>
						<cfloop query="a_criteria">
							<cfif #a_criteria.type_action# EQ "0">
							<dict>
								<key>order</key>
								<string>#a_criteria.type_order#</string>
								<key>data</key>
								<string>#iif( len(a_criteria.type_Data) is not 0, DE( ToBase64(a_criteria.type_Data)), DE("NA"))#</string>
							</dict>
							</cfif>
						</cfloop>
						</array>
						<key>criteria_post</key>
						<array>
						<cfloop query="a_criteria">
							<cfif #a_criteria.type_action# EQ "1">
							<dict>
								<key>order</key>
								<string>#a_criteria.type_order#</string>
								<key>data</key>
								<string>#iif( len(a_criteria.type_Data) is not 0, DE( ToBase64(a_criteria.type_Data)), DE("NA"))#</string>
							</dict>
							</cfif>
						</cfloop>
						</array>
						<cfelse>
						<false/>
						</cfif>
					</dict>
					</cfif>
				</cfoutput></cfloop>
                </array>
                <key>CustomUpdates</key>
                <array>
                	<cfloop list="#thirdIDList#" index="item">
                    <dict>
                    	<key>patches</key>
                        <array>
							<cfset preRes = GetPatchRequisits(item,'0') />
                            <cfset patchRes = GetPatchInfo(item) />
                            <cfset pstRes = GetPatchRequisits(item,'1') />
                            <cfif preRes.recordcount GTE 1>
                            <cfloop query="preRes"><cfoutput>
                            <dict>
                                <key>name</key>
                                <string>#suname#</string>
                                <key>hash</key>
                                <string>#pkgHash#</string>
                                <key>postinst</key>
                                <string>#iif(len(pkgPost) is not 0,DE(ToBase64(pkgPost)),DE("NA"))#</string>
                                <key>preinst</key>
                                <string>#iif(len(pkgPre) is not 0,DE(ToBase64(pkgPre)),DE("NA"))#</string>
                                <key>env</key>
								<string>#iif(len(envVar) is not 0,DE(envVar),DE("NA"))#</string>
								<key>reboot</key>
                                <string>#reboot#</string>
                                <key>type</key>
                                <string>0</string>
                                <key>url</key>
                                <string>#pkgUrl#</string>
                                <key>size</key>
                                <string>0</string>
                            </dict>
                            </cfoutput></cfloop>
                            </cfif>
                            <cfloop query="patchRes"><cfoutput>
                            <dict>
                            	<key>name</key>
                                <string>#suname#</string>
                                <key>hash</key>
                                <string>#pkg_hash#</string>
                                <key>postinst</key>
                                <string>#iif(len(pkg_postinstall) is not 0,DE(ToBase64(pkg_postinstall)),DE("NA"))#</string>
                                <key>preinst</key>
                                <string>#iif(len(pkg_preinstall) is not 0,DE(ToBase64(pkg_preinstall)),DE("NA"))#</string>
                                <key>env</key>
								<string>#iif(len(pkg_env_var) is not 0,DE(pkg_env_var),DE("NA"))#</string>
								<key>reboot</key>
                                <string>#patch_reboot#</string>
                                <key>type</key>
                                <string>1</string>
                                <key>url</key>
                                <string>#pkg_url#</string>
                                <key>size</key>
                                <string>#pkg_size#</string>
                                <key>baseline</key>
                                <string>0</string>
                            </dict>
                            </cfoutput></cfloop>
                            <cfif IsQuery(pstRes) AND pstRes.recordcount GTE 1>
                            <cfloop query="pstRes"><cfoutput>
                            <dict>
                            	<key>name</key>
                                <string>#suname#</string>
                                <key>hash</key>
                                <string>#pkgHash#</string>
                                <key>postinst</key>
                                <string>#iif(len(pkgPost) is not 0,DE(ToBase64(pkgPost)),DE("NA"))#</string>
                                <key>preinst</key>
                                <string>#iif(len(pkgPre) is not 0,DE(ToBase64(pkgPre)),DE("NA"))#</string>
                                <key>env</key>
								<string>#iif(len(envVar) is not 0,DE(envVar),DE("NA"))#</string>
								<key>reboot</key>
                                <string>#reboot#</string>
                                <key>type</key>
                                <string>2</string>
                                <key>url</key>
                                <string>#pkgUrl#</string>
                                <key>size</key>
                                <string>0</string>
                            </dict>
                            </cfoutput></cfloop>
                            </cfif>
                        </array>
                        <key>patch_id</key>
						<string><cfoutput>#item#</cfoutput></string>
                    </dict>
                    </cfloop>
                </array>
            </dict>
            </plist>
        </cfprocessingdirective>
		</cfsavecontent>

		<cfreturn #Trim(thePlist)#>
	</cffunction>

	<cffunction name="GetPatchGroupPatches" access="public" returntype="any" output="no">
        <cfargument name="PatchGroupID" required="yes">

        <cftry>
            <cfquery datasource="#this.ds#" name="qGetUpdatesApple">
            	Select mpg.name, mpgp.patch_id, cpfv.type, cpfv.reboot, cpfv.suname, cpfv.size,
                cpfv.patch_install_weight, cpfv.patch_reboot_override, cpfv.severity,
				CASE WHEN EXISTS
				( SELECT 1
					FROM mp_apple_patch_criteria v
					WHERE v.puuid = mpgp.patch_id)
				THEN "1" ELSE "0"
				END AS hasCriteria
                From mp_patch_group mpg
                Join mp_patch_group_patches mpgp
                ON mpg.id = mpgp.patch_group_id
                Join combined_patches_view cpfv
                ON mpgp.patch_id = cpfv.id

                Where mpg.id like <cfqueryparam value="#arguments.PatchGroupID#">
                AND cpfv.type = 'Apple'
            </cfquery>
            <cfcatch type="any">
            <cfinvoke component="ws_logger" method="LogEvent">
                <cfinvokeargument name="aEventType" value="Error">
                <cfinvokeargument name="aHost" value="#CGI.REMOTE_HOST#">
                <cfinvokeargument name="aEvent" value="[GetPatchGroupPatches][qGetUpdatesApple]: #cfcatch.Detail# -- #cfcatch.Message#">
            </cfinvoke>
            </cfcatch>
        </cftry>
        <cftry>
            <cfquery datasource="#this.ds#" name="qGetUpdatesThird">
            	Select mpg.name as name, mpgp.patch_id as id, mpp.bundle_id as bundle_id, cpfv.type as type, cpfv.reboot as reboot, cpfv.suname as suname,  
                mpp.pkg_hash as hash, mpp.pkg_path as path, mpp.pkg_size as size,cpfv.patch_install_weight, cpfv.patch_reboot_override, cpfv.severity
                From mp_patch_group mpg
                Join mp_patch_group_patches mpgp
                ON mpg.id = mpgp.patch_group_id
                Join combined_patches_view cpfv
                ON mpgp.patch_id = cpfv.id
                Join mp_patches mpp
                ON mpp.puuid = mpgp.patch_id

                Where mpg.id like <cfqueryparam value="#arguments.PatchGroupID#">
                AND cpfv.type = 'Third'
            </cfquery>
            <cfcatch type="any">
            <cfinvoke component="ws_logger" method="LogEvent">
                <cfinvokeargument name="aEventType" value="Error">
                <cfinvokeargument name="aHost" value="#CGI.REMOTE_HOST#">
                <cfinvokeargument name="aEvent" value="[GetPatchGroupPatches][qGetUpdatesThird]: #cfcatch.Detail# -- #cfcatch.Message#">
            </cfinvoke>
            </cfcatch>
        </cftry>

        <cfset thirdIDList = ValueList(qGetUpdatesThird.id)>
        <cfset var a_criteria = QueryNew("puuid, supatchname, type, type_order, type_action, type_data")>  />
		
		<cfset response = {} />
        <cfset response[ "rev" ] = '-1' />
		<cfset response[ "AppleUpdates" ] = {} />
		<cfset _AppleUpdates = arrayNew(1)>
		<cfset response[ "CustomUpdates" ] = {} />
		<cfset _CustomUpdates = arrayNew(1)>
		
		<!--- Build the Apple Updates Struct --->
		<cfloop query="qGetUpdatesApple">
			<cfset _aUpdate = {} />
			<cfset _aUpdate[ "name" ] = "#Trim(suname)#" />
			<cfset _aUpdate[ "patchid" ] = "#patch_id#" />
			<cfset _aUpdate[ "baseline" ] = "0" />
            <cfset _aUpdate[ "patch_install_weight" ] = "#patch_install_weight#" />
            <cfset _aUpdate[ "patch_reboot_override" ] = "#patch_reboot_override#" />
            <cfset _aUpdate[ "severity" ] = "#severity#" />
			<cfif #hasCriteria# EQ "0">
				<cfset _aUpdate[ "hasCriteria" ] = "FALSE" />
			<cfelse>
				<cfset _aUpdate[ "hasCriteria" ] = "TRUE" />
				<cfset _aUpdate[ "criteria_pre" ] = "" />
				<cfloop query="a_criteria">
					<cfset _criteria_pre = arrayNew(1)>
					<cfif #a_criteria.type_action# EQ "0">
						<cfset _pre = {} />
						<cfset _pre[ "order" ] = "#a_criteria.type_order#" />
						<cfset _pre[ "data" ] = "#iif( len(a_criteria.type_Data) is not 0, DE( ToBase64(a_criteria.type_Data)), DE('NA'))#" />
						<cfset b = ArrayAppend(_criteria_pre,_pre)>
					</cfif>
				</cfloop>
				<cfset _aUpdate[ "criteria_post" ] = "" />
				<cfloop query="a_criteria">
					<cfset _criteria_post = arrayNew(1)>
					<cfif #a_criteria.type_action# EQ "1">
						<cfset _post = {} />
						<cfset _post[ "order" ] = "#a_criteria.type_order#" />
						<cfset _post[ "data" ] = "#iif( len(a_criteria.type_Data) is not 0, DE( ToBase64(a_criteria.type_Data)), DE('NA'))#" />
						<cfset c = ArrayAppend(_criteria_post,_post)>
					</cfif>
				</cfloop>		
			</cfif>
			<cfset a = ArrayAppend(_AppleUpdates,_aUpdate)>
		</cfloop>
		<cfset response.AppleUpdates = _AppleUpdates />
		
		<!--- Build the Custom Updates Struct --->
		<cfloop list="#thirdIDList#" index="item">
			<cfset preRes = GetPatchRequisits(item,'0') />
            <cfset patchRes = GetPatchInfo(item) />
            <cfset pstRes = GetPatchRequisits(item,'1') />
			
			<!--- Main Dict for the Patch --->	
			<cfset _cUpdate = {} />
			<cfset _cUpdate[ "patch_id" ] = "#item#" />
            <cfset _cUpdate[ "bundle_id" ] = "#patchRes.bundle_id#" />
            <cfset _cUpdate[ "patch_install_weight" ] = "#patchRes.patch_install_weight#" />
			<cfset _cUpdate[ "patches" ] = "" />
            <cfset _cUpdate[ "severity" ] = "#patchRes.patch_severity#" />
			<cfset _cUpdate_Patches = arrayNew(1)>
			<!--- Patches for the patch id --->
			<cfif preRes.recordcount GTE 1>
				<cfloop query="preRes">
					<cfset _a = {} />
					<cfset _a[ "name" ] = "#suname#" />
					<cfset _a[ "hash" ] = "#pkgHash#" />
					<cfset _a[ "preinst" ] = "#iif(len(pkgPre) is not 0,DE(ToBase64(pkgPre)),DE('NA'))#" />
					<cfset _a[ "postinst" ] = "#iif(len(pkgPost) is not 0,DE(ToBase64(pkgPost)),DE('NA'))#" />
					<cfset _a[ "env" ] = "#iif(len(envVar) is not 0,DE(envVar),DE('NA'))#" />
					<cfset _a[ "reboot" ] = "#reboot#" />
					<cfset _a[ "type" ] = "0" />
					<cfset _a[ "url" ] = "#pkgUrl#" />
					<cfset _a[ "size" ] = "0" />
					<cfset pa = ArrayAppend(_cUpdate_Patches,_a)>
				</cfloop>
			</cfif>
				<cfloop query="patchRes">
					<cfset _b = {} />
					<cfset _b[ "name" ] = "#suname#" />
					<cfset _b[ "hash" ] = "#pkg_hash#" />
					<cfset _b[ "preinst" ] = "#iif(len(pkg_preinstall) is not 0,DE(ToBase64(pkg_preinstall)),DE('NA'))#" />
					<cfset _b[ "postinst" ] = "#iif(len(pkg_postinstall) is not 0,DE(ToBase64(pkg_postinstall)),DE('NA'))#" />
					<cfset _b[ "env" ] = "#iif(len(pkg_env_var) is not 0,DE(pkg_env_var),DE("NA"))#" />
					<cfset _b[ "reboot" ] = "#patch_reboot#" />
					<cfset _b[ "type" ] = "1" />
					<cfset _b[ "url" ] = "#pkg_url#" />
					<cfset _b[ "size" ] = "#pkg_size#" />
					<cfset _b[ "baseline" ] = "0" />
					<cfset pa = ArrayAppend(_cUpdate_Patches,_b)>
				</cfloop>
			<cfif IsQuery(pstRes) AND pstRes.recordcount GTE 1>
				<cfloop query="pstRes">
					<cfset _c = {} />
					<cfset _c[ "name" ] = "#suname#" />
					<cfset _c[ "hash" ] = "#pkgHash#" />
					<cfset _c[ "preinst" ] = "#iif(len(pkgPre) is not 0,DE(ToBase64(pkgPre)),DE('NA'))#" />
					<cfset _c[ "postinst" ] = "#iif(len(pkgPost) is not 0,DE(ToBase64(pkgPost)),DE('NA'))#" />
					<cfset _c[ "env" ] = "#iif(len(envVar) is not 0,DE(envVar),DE('NA'))#" />
					<cfset _c[ "reboot" ] = "#reboot#" />
					<cfset _c[ "type" ] = "2" />
					<cfset _c[ "url" ] = "#pkgUrl#" />
					<cfset _c[ "size" ] = "0" />
					<cfset pa = ArrayAppend(_cUpdate_Patches,_c)>
				</cfloop>
			</cfif>	
			<cfset _cUpdate.patches = _cUpdate_Patches />
			<cfset c = ArrayAppend(_CustomUpdates,_cUpdate)>
		</cfloop>
		<cfset response.CustomUpdates = _CustomUpdates />
		
		<cfreturn SerializeJSON(response)>
	</cffunction>
<!---	--->

<!--- #################################################### --->
<!--- HELPERS -- GetPatchRequisits 						   --->
<!--- #################################################### --->
    <cffunction name="GetPatchRequisits" access="public" returntype="query" output="no">
    	<cfargument name="id" required="yes">
        <cfargument name="type" required="yes">

         <cfquery datasource="#this.ds#" name="qGetPatchRequisits" result="res" debug="yes" cachedwithin="#CreateTimeSpan(0, 0, 0, 30)#">
            select mpr.type_order as type_order, mpp.pkg_preinstall as pkgPre, mpp.pkg_postinstall as pkgPost, mpp.pkg_hash as pkgHash, mpp.pkg_url as pkgUrl, mpp.patch_reboot as reboot, CONCAT_WS('-',mpp.patch_name, mpp.patch_ver) as suname, pkg_env_var as envVar
            from mp_patches_requisits mpr
            Join mp_patches mpp
            ON mpr.puuid_ref = mpp.puuid
            Where mpr.puuid = <cfqueryparam value="#arguments.id#">
            AND mpp.active = '1'
            AND mpr.type = <cfqueryparam value="#arguments.type#">
            Order By mpr.type_order Asc
        </cfquery>

    	<cfreturn qGetPatchRequisits>
    </cffunction>

	<cffunction name="GetApplePatchCriteria" access="public" returntype="query" output="no">
    	<cfargument name="id" required="yes">

         <cfquery datasource="#this.ds#" name="qGetApplePatchCriteria" result="res" cachedwithin="#CreateTimeSpan(0, 0, 0, 30)#">
			select puuid, supatchname, type, type_order, type_action, type_data From mp_apple_patch_criteria
			Where puuid = '#arguments.id#'
			Order By type_action, type_order Asc
        </cfquery>

    	<cfreturn qGetApplePatchCriteria>
    </cffunction>

    <cffunction name="GetPatchInfo" access="public" returntype="query" output="no">
    	<cfargument name="id" required="yes">

        <cfquery datasource="#this.ds#" name="qGetPatchInfo" cachedwithin="#CreateTimeSpan(0, 0, 0, 30)#">
            select mpp.*, CONCAT_WS('-',mpp.patch_name, mpp.patch_ver) as suname
            from mp_patches mpp
            Where puuid = <cfqueryparam value="#arguments.id#">
        </cfquery>

    	<cfreturn qGetPatchInfo>
    </cffunction>
</cfcomponent>    