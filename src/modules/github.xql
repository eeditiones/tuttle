xquery version "3.1";

module namespace github="http://e-editiones.org/tuttle/github";

import module namespace crypto="http://expath.org/ns/crypto";

import module namespace app="http://e-editiones.org/tuttle/app" at "app.xql";
import module namespace config="http://e-editiones.org/tuttle/config" at "config.xql";

declare namespace http="http://expath.org/ns/http-client";

declare function github:repo-url($config as map(*)) as xs:string {
    ``[`{$config?baseurl}`repos/`{$config?owner}`/`{$config?repo}`]``
};

(:
  The `commits` API endpoint is _paged_ and will only return _30_ commits by default
  it is possible to add the parameter `&per_page=100` (100 being the maximum)
  But this will _always_ return 100 commits, which might result in to much overhead
  and still might not be enough.

  Pagination: https://docs.github.com/en/rest/guides/using-pagination-in-the-rest-api?apiVersion=2022-11-28
 :)
declare function github:commit-ref-url($config as map(*)) as xs:string {
    github:repo-url($config) || "/commits?sha=" || $config?ref
};

declare function github:commit-ref-url($config as map(*), $per-page as xs:integer) as xs:string {
    github:commit-ref-url($config) || "&amp;per_page=" || $per-page
};

(:~
 : Clone defines Version repo
 :)
declare function github:clone($config as map(*), $collection as xs:string, $sha as xs:string?) as map(*) {
    try {
        let $zip := github:request(
            github:repo-url($config) || "/zipball/" || $sha, $config?token)

        let $delete-collection :=
            if (xmldb:collection-available($collection))
            then xmldb:remove($collection)
            else ()

        let $create-collection := xmldb:create-collection("/", $collection)

        let $write-sha := app:write-sha($collection,
            if (exists($sha)) then $sha else github:get-last-commit($config)?sha)
        
        let $clone := app:extract-archive($zip, $collection)

        return map { "message" : "success" }
    }
    catch * {
        map {
            "message": $err:description,
            "_error": map {
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
    }
};

(:~
 : Get the last commit
 :)
declare function github:get-last-commit($config as map(*)) as map(*) {
    array:head(
        github:request-json(
            github:commit-ref-url($config, 1), $config?token))
};

(:~
 : Get all commits
 :)
declare function github:get-commits($config as map(*)) as array(*)* {
    github:get-commits($config, 100)
};

(:~
 : Get N commits
 :)
declare function github:get-commits($config as map(*), $count as xs:integer) as array(*)* {
    if ($count <= 0)
    then error(xs:QName("github:illegal-argument"), "$count must be greater than zero in github:get-commits")
    else
        let $json := github:get-raw-commits($config, $count)
        let $commits :=
            if (empty($json))
            then []
            else if ($count >= array:size($json)) (: return everything :)
            then $json
            else array:subarray($json, 1, $count)
        
        return
            array:for-each($commits, github:short-commit-info#1)
};

declare %private function github:short-commit-info ($commit-info as map(*)) as array(*) {
    [
        app:shorten-sha($commit-info?sha),
        $commit-info?commit?message
    ]
};

declare %private function github:only-commit-shas ($commit-info as map(*)) as array(*) {
    [
        app:shorten-sha($commit-info?sha),
        $commit-info?sha
    ]
};

(:~
 : Get commits in full
 :)
declare function github:get-raw-commits($config as map(*), $count as xs:integer) as array(*)? {
    github:request-json(
        github:commit-ref-url($config, $count), $config?token)
};

(:~ 
 : Get diff between production collection and github-newest
 :)
declare function github:get-newest-commits($config as map(*)) as xs:string* {
    let $deployed := $config?deployed
    let $commits := github:get-raw-commits($config, 100)
    let $shas := array:for-each($commits, github:only-commit-shas#1)?*
    let $how-many := index-of($shas?1, $deployed) - 1
    return reverse(subsequence($shas?2, 1, $how-many))
};

(:~
 : Check if sha exist
 : TODO: github API might offer a better way to check not only if the commit exists
 :       but also if this commit is part of `ref`
 :)
declare function github:available-sha($config as map(*), $sha as xs:string) as xs:boolean {
    $sha = github:get-commits($config)?*?1
};

declare function github:get-changes ($collection-config as map(*)) as map(*) {
    let $changes :=
        for $sha in github:get-newest-commits($collection-config)
        return github:get-commit-files($collection-config, $sha)?*

    (: aggregate file changes :)
    return fold-left($changes, map{}, github:aggregate-filechanges#2)

};

(:~
 : Handle edge case where a file created in this changeset is also removed
 : 
 : So, in order to not fire useless and potentially harmful side-effects like
 : triggers or indexing we filter out all of these documents as if they were
 : never there.
 :)
declare function github:remove-or-ignore ($changes as map(*), $filename as xs:string) as map(*) {
    if ($filename = $changes?new)
    then map:put($changes, "new", $changes?new[. ne $filename]) (: filter document from new :)
    else map:put($changes, "del", ($changes?del, $filename)) (: add document to be removed :)
};

declare function github:aggregate-filechanges ($changes as map(*), $next as map(*)) as map(*) {
    switch ($next?status)
    case "added" (: fall-through :)
    case "modified" return
        map:put($changes, "new", ($changes?new, $next?filename))
    case "renamed" return
        github:remove-or-ignore($changes, $next?previous_filename)
        => map:put("new", ($changes?new, $next?filename))
    case "removed" return
        github:remove-or-ignore($changes, $next?filename)
    default return
        $changes
};

(:~ 
 : Run incremental update on collection in dry mode
 :) 
declare function github:incremental-dry($config as map(*)) {
    let $changes := github:get-changes($config)
    return map {
        'new': array{ $changes?new },
        'del': array{ $changes?del }
    }
};

(:~ 
 : Run incremental update on collection
 :) 
declare function github:incremental($config as map(*)) {
    let $sha := github:get-last-commit($config)?sha
    let $changes := github:get-changes($config)
    let $del := github:incremental-delete($config, $changes?del)
    let $add := github:incremental-add($config, $changes?new, $sha)
    let $writesha := app:write-sha($config?path, $sha)
    return ($del, $add) 
};


(:~
 : Get files removed and added from commit 
 :)
declare function github:get-commit-files($config as map(*), $sha as xs:string) as array(*) {
    let $url := github:repo-url($config) || "/commits/"  || $sha
    let $commit := github:request-json($url, $config?token)

    return $commit?files
};

(:~
 : Get blob of a file
 :)
declare function github:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    let $blob-url := github:repo-url($config) || "/contents/" || escape-html-uri($filename) || "?ref=" || $sha
    let $json := github:request-json($blob-url, $config?token)
    
    return
        util:base64-decode($json?content)
};

(:~
 : Get HTTP-URL
 :)
declare function github:get-url($config as map(*)) {
    let $repo-info := github:request-json(github:repo-url($config), $config?token)
    return $repo-info?html_url
};

(:~ 
 : Check signature for Webhook
 :)
declare function github:check-signature($collection as xs:string, $apikey as xs:string) as xs:boolean {
    let $signature := request:get-header("X-Hub-Signature-256")
    let $payload := util:binary-to-string(request:get-data())
    let $private-key := doc(config:apikeys())//apikeys/collection[name = $collection]/key/string()
    let $expected-signature := "sha256=" || crypto:hmac($payload, $private-key, "HmacSha256", "hex")

    return $signature = $expected-signature
};

(:~ 
 : Incremental updates delete files
 :)
declare %private function github:incremental-delete($config as map(*), $files as xs:string*) {
    for $resource in $files
    let $resource-path := tokenize($resource, '[^/]+$')[1]
    let $resource-collection := $config?path || "/" || $resource-path
    let $resource-filename := xmldb:encode(replace($resource, $resource-path, ""))

    return
        try {
            let $remove := xmldb:remove($resource-collection, $resource-filename)
            let $remove-empty-col := 
                if (empty(xmldb:get-child-resources($resource-collection))) then
                    xmldb:remove($resource-collection)
                    else ()
            return ()
        }
        catch * {
            map {
                "resource": $resource,
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
};

(:~
 : Incremental update fetch and add files from git
 :)
declare %private function github:incremental-add($config as map(*), $files as xs:string*, $sha as xs:string) {
    for $resource in $files
    let $resource-path := tokenize($resource, '[^/]+$')[1]
    let $resource-collection := $config?path || "/" || $resource-path
    let $resource-filename :=
        if ($resource-path = "") then
            xmldb:encode($resource)
        else
            xmldb:encode(replace($resource, $resource-path, ""))

    let $resource-fullpath := $resource-collection || $resource-filename

    return 
        try {
            let $data := github:get-blob($config, $resource, $sha)
            let $collection-check := 
                if (xmldb:collection-available($resource-collection)) then ()
                else (
                    app:mkcol($resource-collection),
                    app:set-permission($config?collection, $resource-collection, "collection")
                )
            let $store := xmldb:store($resource-collection, $resource-filename, $data)
            let $chmod := app:set-permission($config?collection, $resource-fullpath, "resource")
            return ()
        }
        catch * {
            map {
                "resource": $resource,
                "code": $err:code, "description": $err:description, "value": $err:value, 
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }
        }
};

(:~
 : Github request
 :)

(: If the response header `link` contains rel="next", there are commits missing. :)
declare %private function github:has-next-page($response as element(http:response)) {
    let $link-header := $response//http:header/@name[.="link"]
    return contains($link-header, 'rel="next"')
};

declare %private function github:request-json($url as xs:string, $token as xs:string?) {
    let $response := app:request-json(github:build-request($url, $token))

    return (
        if (github:has-next-page($response[1]))
        then util:log("warn", ('Paged github request has next page! URL:', $url))
        else (),
        $response[2]
    )
};

declare %private function github:request($url as xs:string, $token as xs:string?) {
    app:request(github:build-request($url, $token))[2]
};

declare %private function github:build-request($url as xs:string, $token as xs:string?) as element(http:request) {
    <http:request http-version="1.1" href="{$url}" method="get">
        <http:header name="Accept" value="application/vnd.github.v3+json" />
        {
            if (empty($token) or $token = "")
            then ()
            else <http:header name="Authorization" value="token {$token}"/>
        }
    </http:request>
};
