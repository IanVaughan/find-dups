require 'digest'
require 'pry'
require 'yaml'
require 'ruby-progressbar'
require 'highline/import'

BASE_PATH = '/tmp/dups'
# Dir.mkdir(BASE_PATH)

def file_exist?(filename)
  File.exist? File.join(BASE_PATH, filename)
end

def save(data, filename)
  File.open(File.join(BASE_PATH, filename), 'w') {|f| f.write(YAML.dump(data)) }
end

def read(filename)
  YAML.load(File.read(File.join(BASE_PATH, filename)))
end

def reset?
  ARGV[0] == 'reset'
end

def excluded_list
  if file_exist? 'excluded_list'
    File.read(File.join(BASE_PATH, 'excluded_list')).split
  else
    []
  end
end

def find_files
  puts "1. Finding files..."
  files = Dir['./**/*'] # Dir['./**']
  puts "1.1 Removing excluded files"
  files.delete_if { |f| excluded_list.any? { |m| f.match(m) } }
end

def analyse(files)
  hash = Hash.new { |h,k| h[k] = [] }
  errors = []

  pb = ProgressBar.create(title: '2. Analysing', total: files.count, format: '%t : %a |%B| %p%% %c/%C')

  files.each do |file|
    next if File.directory?(file)
    begin
      sha256 = Digest::SHA256.file(file)
      pb.increment
    rescue Errno::ENOENT, Errno::EOPNOTSUPP, Errno::EACCES => e
      errors << [file, e]
    else
      hash[sha256.hexdigest] << file
    end
  end

  [hash, errors]
end

def find_dups(hash)
  pb = ProgressBar.create(title: '3. Finding duplicates', total: hash.count, format: '%t %a %B %p%% %c/%C')
  hash.delete_if { |sha, files| pb.increment; files.count == 1 }
end

def get_sizes(hash)
  pb = ProgressBar.create(title: '4. Calculating sizes', total: hash.count, format: '%t %a %B %p%% %c/%C')

  hash.map do |sha, files|
    found_size = false
    try = 0
    while !found_size
      file = files[try]
      if File.exist? file
        files << File.size(file)
        found_size = true
      else
        try += 1
        if try >= files.count
          files << -1
          found_size = true
        end
      end
    end
    pb.increment
  end

  pb = ProgressBar.create(title: '5. Sorting', total: hash.count, format: '%t %a %B %p%% %c/%C')
  h = hash.sort_by { |sha, files| pb.increment; files.last }
  hash = Hash[h.reverse]

  size = 0
  hash.map { |sha, files| size += files.last * files.count-1 }
  puts "The duplicates consume a total of #{size} in bytes (#{size/1024}M, #{size/1024/1024}Gb)"

  hash
end

def read_or_run(name, reset)
  if file_exist?(name) && !reset
    puts "Loading previous #{name}"
    [read(name), reset]
  else
    result = yield
    save(result, name)
    [result, true]
  end
end

def menu(files, number, total)
  size = files.pop
  puts "#{number}/#{total} These #{files.size} are #{size} big each."
  answer = choose do |menu|
    menu.prompt = '> '
    menu.choices(*files.sort)
    menu.choice(:skip)
    menu.choice(:open)
    menu.choice(:quit)
  end
  return -1 if answer == :skip
  return -2 if answer == :quit # abort if %w(q quit).include?(answer) || answer.empty?
  if answer == :open
    `open #{files.first}`
  else
    FileUtils.move(answer, File.join(Dir.home, '.trash')) if File.exist? answer
    files.delete answer
  end
  if files.count > 1
    files << size
    menu(files, number, total)
  end
end

def ask(sizes, reset = false)
  puts "Found #{sizes.size} duplicates :"
  sizes.values.each_with_index do |h,i|
    ans = menu(h, i, sizes.size)
    exit if ans == -2
  end
end

def run(reset)
  files, reset = read_or_run('files', reset) { find_files }
  hash, reset = read_or_run('analyse', reset) { analyse(files) }
  dups, reset = read_or_run('dups', reset) { find_dups(hash.first) }
  sizes, reset = read_or_run('sizes', reset) { get_sizes(dups) }
  ask(sizes, reset)
end

run reset?
