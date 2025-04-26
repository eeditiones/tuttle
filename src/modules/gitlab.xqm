xquery version "3.1";

module namespace gitlab="http://e-editiones.org/tuttle/gitlab";

import module namespace app="http://e-editiones.org/tuttle/app" at "app.xqm";
import module namespace config="http://e-editiones.org/tuttle/config" at "config.xqm";

declare namespace http="http://expath.org/ns/http-client";

declare function gitlab:repo-url($config as map(*)) as xs:string {
    ``[`{$config?baseurl}`projects/`{$config?project-id}`/repository]``
};

declare function gitlab:commit-by-ref-url($config as map(*), $ref as xs:string) as xs:string {
    gitlab:repo-url($config) || "/commits/" || $ref
};

(:
  the `commits` API endpoint is _paged_ and will only return _20_ commits by default
  ?ref_name={ref}&per_page=100
  will always return 100 commits, which might result in to much overhead
 :)
declare function gitlab:commit-ref-url($config as map(*)) as xs:string {
    gitlab:repo-url($config) || "/commits/?ref_name=" || $config?ref
};

declare function gitlab:commit-ref-url($config as map(*), $per-page as xs:integer) as xs:string {
    gitlab:commit-ref-url($config) || "&amp;per_page=" || $per-page
};

(:
  The Gitlab API allows to specify a revision range as the value for ref_name
  ?ref_name={ref}...{deployed_hash}
  This will only retrieve commits since deployed_hash but the result is paged as well.

  ?ref_name={ref}...{deployed_hash}&per_page=100
  will return _up to_ 100 commits until deployed_hash is reached.
 :)
declare function gitlab:newer-commits-url($config as map(*), $base as xs:string, $per-page as xs:integer) as xs:string {
    gitlab:repo-url($config) || "/commits?ref_name=" || $config?ref || "..." || $base || "&amp;per_page=" || $per-page
};

(:~
 : clone defines Version repo
 :)
declare function gitlab:get-archive($config as map(*), $sha as xs:string) {
    gitlab:request(
        gitlab:repo-url($config) || "/archive.zip?sha=" || $sha, $config?token)
};

(:~
 : Get commit info for a specific sha
 :)
declare function gitlab:get-specific-commit($config as map(*), $ref as xs:string) as map(*) {
    let $commit :=
        gitlab:request-json(
            gitlab:commit-by-ref-url($config, $ref), $config?token)

    return
        map {
            "sha" : $commit?id,
            "date": $commit?committed_date
        }
};

(:~
 : Get the last commit
 :)
declare function gitlab:get-last-commit($config as map(*)) {
    let $commit :=
        array:head(
            gitlab:request-json(
                gitlab:commit-ref-url($config, 1), $config?token))

    return
        map {
            "sha" : $commit?id,
            "date": $commit?committed_date
        }
};

(:~
 : Get all commits
 :)
declare function gitlab:get-commits($config as map(*)) as array(*)* {
    gitlab:get-commits($config, 100)
};

(:~
 : Get N commits
 :)
declare function gitlab:get-commits($config as map(*), $count as xs:integer) as array(*)* {
    if ($count <= 0)
    then error(xs:QName("gitlab:illegal-argument"), "$count must be greater than zero in gitlab:get-commits")
    else
        let $json := gitlab:get-raw-commits($config, $count)
        let $commits :=
            if (empty($json))
            then []
            else if ($count >= array:size($json)) (: return everything :)
            then $json
            else array:subarray($json, 1, $count)

        return
            array:for-each($commits, gitlab:short-commit-info#1)
};

declare %private function gitlab:short-commit-info ($commit-info as map(*)) as array(*) {
    [
        $commit-info?id,
        $commit-info?message
    ]
};

(:~
 : Get commits in full
 :)
declare function gitlab:get-raw-commits($config as map(*), $count as xs:integer) as array(*)? {
    gitlab:request-json(
        gitlab:commit-ref-url($config, $count), $config?token)
};

(:~
 : Get diff between production collection and gitlab-newest
 :)
declare function gitlab:get-newest-commits($config as map(*)) {
    reverse(
        gitlab:request-json(
            gitlab:newer-commits-url($config, $config?deployed, 100), $config?token)
        ?*)
};

(:~
 : Check if sha exist
 :)
declare function gitlab:available-sha($config as map(*), $sha as xs:string) as xs:boolean {
    $sha = gitlab:get-commits($config)?*?1
};

(:~
 : Get files removed and added from commit
 :)
declare function gitlab:get-commit-files($config as map(*), $sha as xs:string) as array(*) {
    gitlab:request-json(
        gitlab:repo-url($config) || "/commits/" || $sha || "/diff?per_page=100", $config?token)
};

(:~
 : Get blob of a file
 :)
declare function gitlab:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    let $file := escape-html-uri(replace($filename,"/", "%2f"))
    let $file-url := gitlab:repo-url($config) || "/files/" || $file || "?ref=" || $sha
    let $json := gitlab:request-json($file-url, $config?token)

    return
        util:base64-decode($json?content)
};

(:~
 : Get HTTP-URL
 :)
declare function gitlab:get-url($config as map(*)) {
    let $info := gitlab:request-json($config?baseurl || "/projects/" || $config?project-id, $config?token)

    return $info?http_url_to_repo
};

(:~
 : Handle edge case where a file created in this changeset is also removed
 :
 : So, in order to not fire useless and potentially harmful side-effects like
 : triggers or indexing we filter out all of these documents as if they were
 : never there.
 :)
declare function gitlab:remove-or-ignore ($changes as map(*), $filename as xs:string) as map(*) {
    if ($filename = $changes?new)
    then map:put($changes, "new", $changes?new[. ne $filename]) (: filter document from new :)
    else map:put($changes, "del", ($changes?del, $filename)) (: add document to be removed :)
};

declare %private function gitlab:aggregate-filechanges($changes as map(*), $next as map(*)) as map(*) {
    if ($next?renamed_file) then
        gitlab:remove-or-ignore($changes, $next?old_path)
        => map:put("new", ($changes?new, $next?new_path))
    else if ($next?deleted_file) then
        gitlab:remove-or-ignore($changes, $next?new_path)
    (: added or modified :)
    else if ($next?new_file or $next?new_path = $next?old_path) then
        map:put($changes, "new", ($changes?new, $next?new_path))
    else $changes
};

declare function gitlab:get-changes ($collection-config as map(*)) as map(*) {
    let $changes :=
        for $commit in gitlab:get-newest-commits($collection-config)
        return gitlab:get-commit-files($collection-config, $commit?short_id)?*

    let $aggregated := fold-left($changes, map{}, gitlab:aggregate-filechanges#2)
    let $filtered := fold-left($aggregated?new, map{}, app:ignore-reducer#2)
    return map {
        "del": $aggregated?del,
        "new": $filtered?new,
        "ignored": $filtered?ignored
    }
};

(:~
 : Run incremental update on collection in dry mode
 :)
declare function gitlab:incremental-dry($config as map(*)) as map(*) {
    let $changes := gitlab:get-changes($config)
    return map {
        'new': array{ $changes?new },
        'del': array{ $changes?del },
        'ignored': array{ $changes?ignored }
    }
};

(:~
 : Run incremental update on collection
 :)
declare function gitlab:incremental($config as map(*)) as map(*) {
    let $last-commit := gitlab:get-last-commit($config)
    let $changes := gitlab:get-changes($config)
    let $new := gitlab:incremental-add($config, $changes?new, $last-commit?sha)
    let $del := gitlab:incremental-delete($config, $changes?del)
    let $writesha := app:write-commit-info($config?path, $last-commit)
    return map {
        'new': array{ $new },
        'del': array{ $del },
        'ignored': array{ $changes?ignored }
    }
};

declare function gitlab:check-signature ($collection as xs:string, $apikey as xs:string) as xs:boolean {
    request:get-header("X-Gitlab-Token") = $apikey
};

(:~
 : Incremental updates delete files
 :)
declare %private function gitlab:incremental-delete($config as map(*), $files as xs:string*) as array(*)* {
    for $filepath in $files
    return
        try {
            [ $filepath, app:delete-resource($config, $filepath) ]
        }
        catch * {
            [ $filepath, false(), map{
                "code": $err:code, "description": $err:description, "value": $err:value,
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }]
        }
};

(:~
 : Incremental update fetch and add files from git
 :)
declare %private function gitlab:incremental-add($config as map(*), $files as xs:string*, $sha as xs:string) as array(*)* {
    for $filepath in $files
    return
        try {
            [ $filepath,
                app:add-resource($config, $filepath,
                    gitlab:get-blob($config, $filepath, $sha))]
        }
        catch * {
            [ $filepath, false(), map{
                "code": $err:code, "description": $err:description, "value": $err:value,
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }]
        }
};

(:~
 : Gitlab request
 :)

(: If the response header `x-next-page` has a value, there are commits missing. :)
declare %private function gitlab:has-next-page($response as element(http:response)) as xs:boolean {
    let $x-next-page := $response//http:header[@name="x-next-page"]
    return exists($x-next-page/@value) and $x-next-page/@value/string() ne ''
};

declare %private function gitlab:request-json($url as xs:string, $token as xs:string?) {
    let $response := app:request-json(gitlab:build-request($url, $token))

    return (
        if (gitlab:has-next-page($response[1]))
        then util:log("warn", ('Paged gitlab request has next page! URL:', $url))
        else (),
        $response[2]
    )
};

declare %private function gitlab:request($url as xs:string, $token as xs:string?) {
    app:request(gitlab:build-request($url, $token))[2]
};

declare %private function gitlab:build-request($url as xs:string, $token as xs:string) as element(http:request) {
    <http:request http-version="1.1" href="{$url}" method="get">
        {
            if (empty($token) or $token = "")
            then ()
            else <http:header name="PRIVATE-TOKEN" value="{$token}"/>
        }
    </http:request>
};
