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
 : Scan the changeset for an updated expath-pkg.xml
 : update the version that exist-db reports for this package by
 : "installing" a stub
 :)
declare function cb:check-version ($collection-config as map(*), $changes as map(*)) {
    if (cb:changes-array-contains-path($changes?new, $cb:package-descriptor)) then (
        cb:update-package-version($collection-config?path)
    ) else ()
};

declare function cb:changes-array-contains-path($array as array(*), $path as xs:string) as xs:boolean {
    exists(
        array:filter($array, function ($change as map(*)) { $change?path eq $path })?1)
};

declare function cb:update-package-version($target-collection as xs:string) {
    let $path-to-descriptor := $target-collection || "/" || $cb:package-descriptor
    if (not(doc-available($path-to-descriptor))) then (
        "Failure: package descriptor does not exist even though it was updated"
    ) else (
        try {
            let $expath-package-meta := doc($path-to-descriptor)//expath:package
            let $package-name := $expath-package-meta/@name/string()
            (: remove package? :)
            let $stub-name := concat($expath-pkg/@abbrev, "-", $expath-pkg/@version, "__stub.xar")
            let $xar := cb:create-stub-package($target-collection, $stub-name)
            let $installed := cb:install-stub-package($stub-name)
            return "updated"
        } catch * {
            "Failure: " || $err:description
        }
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
        (: $target, needed? :)
        xmldb:get-child-resources($collection)[. = ("expath-pkg.xml", "repo.xml", "exist.xml")][starts-with(., "icon")]
    )
    return
        xs:anyURI($collection || "/" || $resource)
};

declare %private function cb:install-stub-package($xar-name as xs:string) {
    repo:install-from-db($cb:temp-collection || "/" || $xar-name),
    xmldb:remove($cb:temp-collection, $xar-name)
};
