describe file("/usr/local/bin/import") do
  it { should be_executable.by_user("spyglass") }
end
