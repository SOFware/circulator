SimpleCov.start do
  add_filter "/test/"
  add_filter "/lib/circulator/version.rb"

  minimum_coverage 100
end
