function Get-Slug {
    param([String] $name)
    $slug = $name.ToLower()
    $slug = $slug -replace  "[^a-z0-9\s-]", ""
    $slug = $($slug -replace "[\s-]+", " ").Trim()
    $slug = $slug.Substring(0, $slug.Length).Trim()
    $slug = $slug -replace "\s", "-"
    return $slug
}

Export-ModuleMember -function 'Get-*'