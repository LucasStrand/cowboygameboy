local SourceRef = {}

function SourceRef.new(spec)
    spec = spec or {}
    return {
        owner_actor_id = spec.owner_actor_id or "unknown_actor",
        owner_source_type = spec.owner_source_type or "unknown_source_type",
        owner_source_id = spec.owner_source_id or "unknown_source_id",
        parent_source_id = spec.parent_source_id,
    }
end

return SourceRef
