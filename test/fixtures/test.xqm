xquery version "3.1";
(: 
 : custom tuttle callback function for testing
 :)
module namespace test="//test";

(: 
 the first argument is the collection configuration as a map

 example changes

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

each array member in del, new and ignored is a 

record action-result(
 "path": xs:string,
 "success": xs:boolean,
 "error"?: xs:error()
)
:)
declare function test:test ($collection-config as map(*), $changes as map(*)) as item()* {
    map{
        "callback": "test:test",
        "arguments": map{
            "config": $collection-config, 
            "changes": $changes
        }
    }
};