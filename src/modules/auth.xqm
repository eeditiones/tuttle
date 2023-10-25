module namespace auth="http://eeditiones.org/xquery/auth";

import module namespace plogin="http://exist-db.org/xquery/persistentlogin"
    at "java:org.exist.xquery.modules.persistentlogin.PersistentLoginModule";

import module namespace request = "http://exist-db.org/xquery/request";
import module namespace response = "http://exist-db.org/xquery/response";
import module namespace session = "http://exist-db.org/xquery/session";

declare variable $auth:default-options := map {
    "isDba": false(),
    "path": request:get-context-path(),
    "maxAge": xs:dayTimeDuration("P1D"),
    "domain": "exist.org.login"
};

declare function auth:login($user as xs:string, $password as xs:string, $options as map(*)) {
    let $merged-options := map:merge(($auth:default-options, $options), map{ "duplicates": "use-last" })
    let $cookie := request:get-cookie-value($options?domain)
    return
        if (exists($cookie) and $cookie != "deleted") then (
            auth:get-credentials($cookie)
        ) else if ($user) then (
            auth:create-login-session($user, $password, $merged-options)
        ) else (
            (: auth:get-credentials-from-session($merged-options?domain) :)
        )
};

declare function auth:logout ($options as map(*)) {
    let $merged-options := map:merge(($auth:default-options, $options), map{ "duplicates": "use-last" })
    return auth:clear-credentials((), $merged-options)
};

declare %private function auth:callback(
    $newToken as xs:string?,
    $user as xs:string,
    $password as xs:string,
    $expiration as xs:duration,

    $options as map(*)
) {
    if ($options?asDba and not(sm:is-dba($user))) then (
        (: ----------- error ---------- :)
    ) else (
        session:set-attribute($options?domain || ".user", $user),
        request:set-attribute($options?domain || ".user", $user),
        if ($newToken) then (
            response:set-cookie($options?domain, $newToken, $expiration, false(), (), $options?path)
        ) else (),
        $user
    )
};

declare function auth:get-credentials($token as xs:string) {
    plogin:login($token, function (
        $newToken as xs:string?,
        $user as xs:string,
        $password as xs:string,
        $expiration as xs:duration
    ){
        (: util:log("info", ($newToken, $user, $password, $expiration)), :)
        $user
    })
};

declare %private function auth:create-login-session($user as xs:string, $password as xs:string, $options as map(*)) {
    session:invalidate(),
    plogin:register($user, $password, $options?maxAge,
        auth:callback(?, ?, ?, ?, $options))
};

declare %private function auth:clear-credentials($token as xs:string?, $options as map(*)) {
    response:set-cookie($options?domain, "deleted", xs:dayTimeDuration("-P1D"), false(), (), $options?path),
    if ($token and $token != "deleted") then (
        plogin:invalidate($token)
    ) else (),
    session:invalidate()
};

(:~
 : If "remember me" is not enabled (no duration passed), fall back to the usual
 : session-based login mechanism.
 :)
declare %private function auth:fallback-to-session($user as xs:string, $password as xs:string, $options as map(*)) {
    if (
        not(xmldb:login("/db", $user, $password, true())) 
        or ($options?asDba and not(sm:is-dba($user)))
    ) then (
        (: not logged in :)
    ) else (
        session:set-attribute($domain || ".user", $user),
        request:set-attribute($domain || ".user", $user)
    )
};

declare %private function auth:get-credentials-from-session($domain as xs:string) {
    let $userFromSession := session:get-attribute($domain || ".user")
    return (
        request:set-attribute($domain || ".user", $userFromSession)
    )
};
