"""Pinned sources for contract-qualified comparisons with other GA libraries.

An artifact supplies an immutable source tree. It does not certify that the
library builds, implements a particular operation, or matches an existing
GaramonBench comparison group.
"""
const EXTERNAL_GA_SOURCES = (
    (name="gatl", artifact="ga_gatl",
     revision="1f487a70f9c0d29528b7edccf441092bdd2d34f0",
     directory="gatl-1f487a70f9c0d29528b7edccf441092bdd2d34f0",
     marker="cpp/include/gatl/ga3e.hpp", proposed_contract="generic_euclidean"),
    (name="versor", artifact="ga_versor",
     revision="8262fce98c99ea6d9f0984d2ac17cde9fe5d0519",
     directory="versor-8262fce98c99ea6d9f0984d2ac17cde9fe5d0519",
     marker="include/vsr/vsr.h", proposed_contract="generic_euclidean"),
    (name="gal", artifact="ga_gal",
     revision="e859994aeb826acaf912b3efe5813582b0648291",
     directory="gal-e859994aeb826acaf912b3efe5813582b0648291",
     marker="public/gal/geometric_algebra.hpp", proposed_contract="generic_euclidean"),
    (name="klein", artifact="ga_klein",
     revision="21823fc90d191c68a4f31e0b233c58ea28ca3d5a",
     directory="klein-21823fc90d191c68a4f31e0b233c58ea28ca3d5a",
     marker="public/klein/line.hpp", proposed_contract="pga3_specialized"),
    (name="gafro", artifact="ga_gafro",
     revision="5a8a5ec2cfd0d80b74017565f50824b9571a7e69",
     directory="gafro-5a8a5ec2cfd0d80b74017565f50824b9571a7e69",
     marker="src/gafro/gafro.hpp", proposed_contract="robotics_cga_specialized"),
    (name="grassmann_jl", artifact="ga_grassmann_jl",
     revision="4f79a7fdb2d569bf6c13751fad3c078b6c135283",
     directory="Grassmann.jl-4f79a7fdb2d569bf6c13751fad3c078b6c135283",
     marker="Project.toml", proposed_contract="generic_euclidean"),
)

function _external_ga_spec(name::AbstractString)
    selected=filter(spec->spec.name==lowercase(name),EXTERNAL_GA_SOURCES)
    length(selected)==1 || throw(ArgumentError("unknown external GA source: $name"))
    only(selected)
end

"""List source provenance and local artifact availability without downloading."""
function external_ga_candidates()
    [begin
        hash=Pkg.Artifacts.artifact_hash(spec.artifact,CPP_ARTIFACT_TOML)
        isnothing(hash) && error("external GA artifact entry missing: "*spec.artifact)
        Dict{String,Any}(
            "name"=>spec.name,"artifact"=>spec.artifact,
            "revision"=>spec.revision,"git_tree_sha1"=>string(hash),
            "proposed_contract"=>spec.proposed_contract,
            "status"=>spec.name in ("gal", "versor") ?
                "ega3_vector_product_adapter_oracle_qualified" :
                "source_only_adapter_and_oracle_not_qualified",
            "installed"=>isfile(joinpath(Pkg.Artifacts.artifact_path(hash),
                spec.directory,spec.marker)))
    end for spec in EXTERNAL_GA_SOURCES]
end

"""Install one pinned source tree on demand; return its verified root path."""
function ensure_external_ga_source(name::AbstractString)
    spec=_external_ga_spec(name)
    artifact=Pkg.Artifacts.ensure_artifact_installed(spec.artifact,
        CPP_ARTIFACT_TOML;pkg_server_eligible=false)
    root=joinpath(artifact,spec.directory)
    isfile(joinpath(root,spec.marker)) ||
        error("external GA artifact lacks its expected source marker: "*spec.name)
    root
end
