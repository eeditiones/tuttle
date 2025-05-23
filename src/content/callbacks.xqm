xquery version "3.1";
(:~
    Default callbacks
    
    callbacks must have the signature
    function(map(*), map(*)) as item()*
 :)
module namespace cb="http://e-editiones.org/tuttle/callbacks";

import module namespace collection="http://existsolutions.com/modules/collection";

declare namespace expath="http://expath.org/ns/pkg";

declare variable $cb:package-descriptor := "expath-pkg.xml";
declare variable $cb:package-meta-files := ("expath-pkg.xml", "repo.xml", "exist.xml");

declare variable $cb:temp-collection := "/db/system/repo";

(:~
 : example callback
 : It will just return the arguments the function is called with
 : for documentation and testing purposes
 :
 : the first argument is the collection configuration as a map
 : the second argument is a report of the changes that were applied
 : example changes

map {
    "del": [
        map { "path": "fileD", "success": true() }
    ],
    "new": [
        map { "path": "fileN1", "success": true() }
        map { "path": "fileN2", "success": true() }
        map { "path": "fileN3", "success": false(), "error": map{ "code": "err:XPTY0004", "description": "AAAAAAH!", "value": () } }
    ],
    "ignored": [
        map { "path": "fileD" }
    ]
}

: each array member in del, new and ignored is a 

record action-result(
 "path": xs:string,
 "success": xs:boolean,
 "error"?: xs:error()
)
:)
declare function cb:test ($collection-config as map(*), $changes as map(*)) {
    map{
        "callback": "cb:test",
        "arguments": map{
            "config": $collection-config, 
            "changes": $changes
        }
    }
};

(:~
 : Scan an array like ?new ?del or ?ignored you can find out if it contains a specific path(s)
 : if given more than one path then you need to think of them as being combined with or
 : Example:
 : to check if the repo.xml was added or changed do
 : cb:changes-array-contains-path($changes?new, "repo.xml")
 :)
declare function cb:changes-array-contains-path($array as array(*), $path as xs:string+) as xs:boolean {
    $path = $array?*?path
};

(:~
 : Scan the changeset for an updated expath-pkg.xml
 : update the version that exist-db reports for this package by
 : "installing" a stub
 :)
declare function cb:check-version ($collection-config as map(*), $changes as map(*)) as xs:string {
    if (not(cb:changes-array-contains-path($changes?new, $cb:package-descriptor))) then (
        "Descriptor unchanged"
    ) else if (not(doc-available($collection-config?path || "/" || $cb:package-descriptor))) then (
        error(xs:QName("cb:descriptor-missing"), "Package descriptor does not exist even though it was updated")
    ) else (
        let $expath-package-meta := doc($collection-config?path || "/" || $cb:package-descriptor)/expath:package
        let $new-version := $expath-package-meta/@version/string()
        let $old-version := cb:installed-version($expath-package-meta/@name)

        return
            if ($new-version eq $old-version) then (
                "Version unchanged"
            ) else if ($old-version) then (
                (
                    repo:remove($expath-package-meta/@name),
                    cb:update-package-version($collection-config?path, $expath-package-meta),
                    "Updated from " || $old-version || " to " || $new-version
                )[3]
            ) else (
                cb:update-package-version($collection-config?path, $expath-package-meta),
                "Version set to " || $new-version
            )
    )
};


declare function cb:update-package-version ($target-collection as xs:string, $expath-package-meta as element(expath:package)) {
    let $package-name := $expath-package-meta/@name/string()
    let $stub-name := concat($expath-package-meta/@abbrev, "-", $expath-package-meta/@version, "__stub.xar")
    let $xar := cb:create-stub-package($target-collection, $stub-name)
    
    return cb:install-stub-package($stub-name)
};

declare function cb:installed-version($package-name as xs:string) as xs:string? {
    if (not($package-name = repo:list())) then (
    ) else (
        parse-xml(
            util:binary-to-string(
                repo:get-resource($package-name, $cb:package-descriptor)))
        /expath:package/@version/string()
    )
};

declare %private function cb:create-stub-package($collection as xs:string, $filename as xs:string) {
    (: ensure temp collection exists :)
    let $_ := collection:create($cb:temp-collection)
    let $contents := compression:zip(cb:resources-to-zip($collection), true(), $collection)
    return
        xmldb:store($cb:temp-collection, $filename, $contents, "application/zip")
};

declare %private function cb:resources-to-zip($collection as xs:string) {
    for $resource in (
        xmldb:get-child-resources($collection)[. = $cb:package-meta-files or starts-with(., "icon")]
    )
    return
        xs:anyURI($collection || "/" || $resource)
};

declare %private function cb:install-stub-package($xar-name as xs:string) {
    repo:install-from-db($cb:temp-collection || "/" || $xar-name),
    xmldb:remove($cb:temp-collection, $xar-name)
};
