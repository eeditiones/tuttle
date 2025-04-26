xquery version "3.1";

module namespace github="http://e-editiones.org/tuttle/github";

import module namespace crypto="http://expath.org/ns/crypto";

import module namespace app="http://e-editiones.org/tuttle/app" at "app.xqm";
import module namespace config="http://e-editiones.org/tuttle/config" at "config.xqm";

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
declare function github:get-archive($config as map(*), $sha as xs:string) as xs:base64Binary {
    github:download-file(
        github:repo-url($config) || "/zipball/" || $sha, $config?token)
};

(:~
 : Get the last commit
 :)
declare function github:get-last-commit($config as map(*)) as map(*) {
    array:head(
        github:request-json-ignore-pages(
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
        $commit-info?sha,
        $commit-info?commit?message
    ]
};

(:~
 : Get commits in full
 :)
declare function github:get-raw-commits($config as map(*), $count as xs:integer) as array(*)? {
    github:request-json-ignore-pages(
        github:commit-ref-url($config, $count), $config?token)
};

(:~
 : Get diff between production collection and github-newest
 :)
declare function github:get-newest-commits($config as map(*)) as xs:string* {
    let $deployed := $config?deployed
    let $commits := github:get-raw-commits($config, 100)
    let $sha := $commits?*?sha
    let $how-many := index-of($sha, $deployed) - 1
    return
        if (empty($how-many)) then (
            error(
                xs:QName("github:commit-not-found"),
                'The deployed commit hash ' || $deployed || ' was not found in the list of commits on the remote.')
        ) else (
            reverse(subsequence($sha, 1, $how-many))
        )
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
    let $aggregated := fold-left($changes, map{}, github:aggregate-filechanges#2)
    let $filtered := fold-left($aggregated?new, map{}, app:ignore-reducer#2)
    return map {
        "del": $aggregated?del,
        "new": $filtered?new,
        "ignored": $filtered?ignored
    }
};

(:~
 : Handle edge case where a file created in this changeset is also removed
 :
 : So, in order to not fire useless and potentially harmful side-effects like
 : triggers or indexing we filter out all of these documents as if they were
 : never there.
 :)
declare function github:aggregate-filechanges ($changes as map(*), $next as map(*)) as map(*) {
    switch ($next?status)
    case "added" return
        let $new := map:put($changes, "new", ($changes?new, $next?filename))
        (: if same file was re-added then remove from it "del" list :)
        return map:put($new, "del", $changes?del[. ne $next?filename])
    case "modified" return
        (: add to "new" list, make sure each entry is in there only once :)
        map:put($changes, "new", ($changes?new[. ne $next?filename], $next?filename))
    case "renamed" return
        let $new := map:put($changes, "new", ($changes?new, $next?filename))
        (: account for files that existed, were removed in one commit and then reinstated by renaming a file :)
        return map:put($new, "del", ($changes?del[. ne $next?filename], $next?previous_filename))
    case "removed" return
        (: ignore this document, if it was added _and_ removed in the same changeset :)
        if ($next?filename = $changes?new)
        then map:put($changes, "new", $changes?new[. ne $next?filename])
        (: guard against duplicates in deletions :)
        else map:put($changes, "del", ($changes?del[. ne $next?filename], $next?filename))
    default return
        (: unhandled cases: "copied", "changed", "unchanged" :)
        $changes
};

(:~
 : Run incremental update on collection in dry mode
 :)
declare function github:incremental-dry($config as map(*)) {
    let $changes := github:get-changes($config)
    return map {
        'new': array{ $changes?new },
        'del': array{ $changes?del },
        'ignored': array{ $changes?ignored }
    }
};

(:~
 : Run incremental update on collection
 :)
declare function github:incremental($config as map(*)) {
    let $last-commit := github:get-last-commit($config)
    let $sha := $last-commit?sha
    let $changes := github:get-changes($config)
    let $del := github:incremental-delete($config, $changes?del)
    let $new := github:incremental-add($config, $changes?new, $sha)
    let $writesha := app:write-commit-info($config?path, $sha, $last-commit?commit?committer?date)
    return map {
        'new': array{ $new },
        'del': array{ $del },
        'ignored': array{ $changes?ignored }
    }
};


(:~
 : Get files removed and added from commit
 :)
declare function github:get-commit-files($config as map(*), $sha as xs:string) as array(*) {
    let $url := github:repo-url($config) || "/commits/"  || $sha
    let $commit := github:request-json-all-pages($url, $config?token, ())

    return array { $commit?files?* }
};

(: TODO: make raw url configurable :)
declare variable $github:raw-usercontent-endpoint := "https://raw.githubusercontent.com";

(:~
 : Get blob of a file
 : https://raw.githubusercontent.com/<owner>/<repo>/<sha>/<path>
 :)
declare %private function github:get-blob($config as map(*), $filename as xs:string, $sha as xs:string) {
    if (not(starts-with($config?baseurl, "https://api.github.com"))) then (
        (: for GitHub enterprise we have to query for the download url, this might return the contents directly :)
        let $blob-url := github:repo-url($config) || "/contents/" || escape-html-uri($filename) || "?ref=" || $sha
        let $json := github:request-json($blob-url, $config?token)
        let $content := $json?content

        return
            if ($json?content = "") (: endpoint did not return base64 encoded contents :)
            then github:download-file($json?download_url, $config?token)
            else util:base64-decode($content)
    ) else (
        (: for github.com we can construct the download url :)
        let $blob-url := string-join((
            $github:raw-usercontent-endpoint,
            $config?owner,
            $config?repo,
            $sha,
            escape-html-uri($filename)
        ), "/")
        return github:download-file($blob-url, $config?token)
    )
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
declare %private function github:incremental-delete($config as map(*), $files as xs:string*) as array(*)* {
    for $filepath in $files
    return
        try {
            [ $filepath, app:delete-resource($config, $filepath) ]
        }
        catch * {
            if (contains($err:description, "not found")) then (
                [ $filepath, true()]
            ) else (
                [ $filepath, false(), map{
                    "code": $err:code, "description": $err:description, "value": $err:value,
                    "line": $err:line-number, "column": $err:column-number, "module": $err:module
                }]
            )
        }
};

(:~
 : Incremental update fetch and add files from git
 :)
declare %private function github:incremental-add($config as map(*), $files as xs:string*, $sha as xs:string) as array(*)* {
    for $filepath in $files
    return
        try {
            [ $filepath,
                app:add-resource($config, $filepath,
                    github:get-blob($config, $filepath, $sha))]
        }
        catch * {
            [ $filepath, false(), map{
                "code": $err:code, "description": $err:description, "value": $err:value,
                "line": $err:line-number, "column": $err:column-number, "module": $err:module
            }]
        }
};

(:~
 : Github request
 :)

(:~
 : If the response header `link` contains rel="next", there are commits missing.
  <hc:header
    name="link"
    value="&lt;https://api.github.com/repositories/11208105/commits/5b4d5b48784fc9535aed38d60082f5d60dbb9f1a?page=2&gt;; rel=&#34;next&#34;, &lt;https://api.github.com/repositories/11208105/commits/5b4d5b48784fc9535aed38d60082f5d60dbb9f1a?page=3&gt;; rel=&#34;last&#34;"/>
 :)
declare %private function github:has-next-page($response as element(http:response)) {
    exists($response/http:header[@name="link"])
};

declare %private function github:parse-link-header($link-header as xs:string) as map(*) {
    map:merge(
        tokenize($link-header, ', ')
        ! array { tokenize(., '; ') }
        ! map {
            replace(?2, "rel=""(.*?)""", "$1") : substring(?1, 2, string-length(?1) - 2)
        }
    )
};

declare variable $github:accept-header := <http:header name="Accept" value="application/vnd.github+json" />;

(: api calls :)
declare %private function github:request-json($url as xs:string, $token as xs:string?) {
    let $response :=
        app:request-json(
            github:build-request($url, (
                $github:accept-header,
                github:auth-header($token))
            ))

    return (
        if (github:has-next-page($response[1])) then (
            error(
                xs:QName("github:next-page"),
                'Paged github request has next page! URL:' || $url,
                github:parse-link-header($response[1]/http:header[@name="link"]/@value)?next
            )
        ) else (),
        $response[2]
    )
};

declare %private function github:request-json-all-pages($url as xs:string, $token as xs:string?, $acc) {
    let $response :=
        app:request-json(
            github:build-request($url, (
                $github:accept-header,
                github:auth-header($token))
            ))

    let $next-url :=
        if (github:has-next-page($response[1])) then (
            github:parse-link-header($response[1]/http:header[@name="link"]/@value)?next
        ) else ()

    let $all := ($acc, $response[2])

    return (
        if (exists($next-url)) then (
            github:request-json-all-pages($next-url, $token, $all)
        ) else (
            $all
        )
    )
};

(:~
 : api calls where it is clear that more pages will be returned but we do not need them
 : for instance when the limit is set to 1 result per page when we only need the head commit
 :)
declare %private function github:request-json-ignore-pages($url as xs:string, $token as xs:string?) {
    app:request-json(
        github:build-request($url, (
            $github:accept-header,
            github:auth-header($token))
        ))[2]
};

(: raw file downloads :)
declare %private function github:download-file ($url as xs:string, $token as xs:string?) {
     app:request(
        github:build-request($url,
            github:auth-header($token)))[2]
};

declare %private function github:auth-header($token as xs:string?) as element(http:header)? {
    if (empty($token) or $token = "")
    then ()
    else <http:header name="Authorization" value="token {$token}"/>
};

declare %private function github:build-request($url as xs:string, $headers as element(http:header)*) as element(http:request) {
    <http:request http-version="1.1" href="{$url}" method="get">{ $headers }</http:request>
};
