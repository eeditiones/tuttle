xquery version "3.0";
import module namespace login="http://exist-db.org/xquery/login" at "resource:org/exist/xquery/modules/persistentlogin/login.xql";

declare variable $exist:path external;
declare variable $exist:resource external;
declare variable $exist:controller external;
declare variable $exist:prefix external;
declare variable $exist:root external;

if ($exist:path eq "") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="{request:get-uri()}/"/>
    </dispatch>

(: forward root path to index.xql :)
else if ($exist:path eq "/") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <redirect url="index.html"/>
    </dispatch>
else if ($exist:resource eq 'login') then
    let $loggedIn := login:set-user("org.exist.login", (), false())
    let $user := request:get-attribute("org.exist.login.user")
    return (
        util:declare-option("exist:serialize", "method=json"),
        try {
            <status xmlns:json="http://www.json.org">
                <user>{$user}</user>
                {
                    if ($user) then (
                        for $item in sm:get-user-groups($user) return <groups json:array="true">{$item}</groups>,
                        <dba>{sm:is-dba($user)}</dba>
                    ) else
                        ()
                }
            </status>
        } catch * {
            response:set-status-code(401),
            <status>{$err:description}</status>
        }
    )

(: static HTML page for API documentation should be served directly to make sure it is always accessible :)
else if ($exist:path eq "/index.html") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <set-header name="Content-Type" value="text/html"/>
    </dispatch>
else if ($exist:path eq "/data/tuttle.xml") then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/data/tuttle.xml">
            <set-header name="Cache-Control" value="max-age=31536000"/>
        </forward>
    </dispatch>
else if ($exist:path eq "/api.html" or ends-with($exist:resource, "json")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

(: other images are resolved against the data collection and also returned directly :)
else if (matches($exist:resource, "\.(css)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

else if (matches($exist:resource, "\.(js)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

else if (matches($exist:resource, "\.(js.map)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

else if (matches($exist:resource, "\.(png)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>
else if (matches($exist:resource, "\.(svg)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
    </dispatch>

else if (matches($exist:resource, "\.(png|jpg|jpeg|gif|tif|tiff|txt|mei|js)$", "s")) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/data/{$exist:path}">
            <set-header name="Cache-Control" value="max-age=31536000"/>
        </forward>
    </dispatch>

(: use a different Open API router, needs exist-jwt installed! :)
else if (starts-with($exist:path, '/jwt')) then
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/custom-router.xq">
            <set-header name="Access-Control-Allow-Origin" value="*"/>
            <set-header name="Access-Control-Allow-Credentials" value="true"/>
            <set-header name="Access-Control-Allow-Methods" value="GET, POST, DELETE, PUT, PATCH, OPTIONS"/>
            <set-header name="Access-Control-Allow-Headers" value="Accept, Content-Type, Authorization, X-Auth-Token"/>
            <set-header name="Cache-Control" value="no-cache"/>
        </forward>
    </dispatch>

(: all other requests are passed on the Open API router :)
else
    <dispatch xmlns="http://exist.sourceforge.net/NS/exist">
        <forward url="{$exist:controller}/modules/api.xql">
            <set-header name="Access-Control-Allow-Origin" value="*"/>
            <set-header name="Access-Control-Allow-Credentials" value="true"/>
            <set-header name="Access-Control-Allow-Methods" value="GET, POST, DELETE, PUT, PATCH, OPTIONS"/>
            <set-header name="Access-Control-Allow-Headers" value="Accept, Content-Type, Authorization, X-Start"/>
            <set-header name="Cache-Control" value="no-cache"/>
        </forward>
    </dispatch>