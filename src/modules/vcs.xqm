
module namespace vcs="http://e-editiones.org/tuttle/vcs";

import module namespace github="http://e-editiones.org/tuttle/github" at "github.xql";
import module namespace gitlab="http://e-editiones.org/tuttle/gitlab" at "gitlab.xql";


declare variable $vcs:mappings as map(*) := map {
    "github": map {
        "get-url": github:get-url#1,
        "clone": github:clone#3,
        "get-last-commit": github:get-last-commit#1,
        "get-commits": github:get-commits#2,
        "get-all-commits": github:get-commits#1,
        "incremental-dry": github:incremental-dry#1,
        "incremental": github:incremental#1,
        "check-signature": github:check-signature#2
    },
    "gitlab": map {
        "get-url": gitlab:get-url#1,
        "clone": gitlab:clone#3,
        "get-last-commit": gitlab:get-last-commit#1,
        "get-commits": gitlab:get-commits#2,
        "get-all-commits": gitlab:get-commits#1,
        "incremental-dry": gitlab:incremental-dry#1,
        "incremental": gitlab:incremental#1,
        "check-signature": gitlab:check-signature#2
    }
};

declare variable $vcs:supported-services as xs:string+ := map:keys($vcs:mappings);

declare function vcs:is-known-service ($vcs as xs:string?) as xs:boolean {
    exists($vcs) and $vcs = $vcs:supported-services
};

declare function vcs:get-actions ($vcs as xs:string?) as map(*)? {
    if (vcs:is-known-service($vcs))
    then $vcs:mappings?($vcs)
    else error((), "Unknown VCS: '" || $vcs || "'")
};
