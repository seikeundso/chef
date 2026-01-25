describe file("/usr/local/bin/update") do
  it { should be_executable.by_user("spyglass") }
end

describe service("replicate") do
  it { should be_installed }
end
