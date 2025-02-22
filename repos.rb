require 'fileutils'
require 'open3'
require 'json'

# Function to display colored text
def print_colored(text, color_code)
  puts "#{color_code}#{text}\033[0m"
end

# Function to delete the Squashfs-Iso-Repos folder if it exists
def delete_squashfs_iso_repos_folder
  folder_path = "/mnt/Squashfs-Iso-Repos"
  if Dir.exist?(folder_path)
    command = "sudo rm -rf #{folder_path}"
    result = system(command)
    if !result
      puts "Error: Failed to delete Squashfs-Iso-Repos folder."
      return false
    end
    puts "Deleted existing Squashfs-Iso-Repos folder."
  end
  true
end

# Function to download repos.txt using git clone
def download_repos_txt
  repo_url = "https://github.com/claudemods/Squashfs-Iso-Repos.git"
  clone_command = "git clone #{repo_url} /tmp/Squashfs-Iso-Repos"
  result = system(clone_command)
  if !result
    puts "Error: Failed to clone repository."
    return false
  end
  puts "Repository cloned successfully."
  true
end

# Function to mount a SquashFS file
def mount_squashfs(squashfs_path, mount_point)
  unless Dir.exist?(mount_point)
    FileUtils.mkdir_p(mount_point)
    puts "Created mount point directory: #{mount_point}"
  end
  command = "sudo mount -t squashfs #{squashfs_path} #{mount_point}"
  result = system(command)
  if !result
    puts "Failed to mount squashfs"
    return false
  end
  puts "Mounted squashfs successfully at: #{mount_point}"
  true
end

# Function to unmount a SquashFS file
def unmount_squashfs(mount_point)
  command = "sudo umount #{mount_point}"
  result = system(command)
  if !result
    puts "Failed to unmount"
    return false
  end
  puts "Unmounted successfully."
  true
end

# Function to download a file using wget
def download_file_with_wget(download_link, output_file_path)
  # Fix Google Drive download link
  if download_link.include?("drive.google.com")
    file_id = download_link.match(/id=([^&]+)/)[1]
    download_link = "https://drive.google.com/uc?export=download&id=#{file_id}"
  end

  command = "sudo wget --no-check-certificate '#{download_link}' -O #{output_file_path}"
  print_colored("Executing command: #{command}\n", "\033[32m") # Green color
  result = system(command)
  if !result
    puts "Download failed: #{$!}"
    return false
  end
  puts "Download completed successfully."
  true
end

# Function to extract the base package name (without version numbers)
def extract_base_package_name(file_path)
  file_name = File.basename(file_path)
  match = file_name.match(/^(.+?)-\d+/)
  match ? match[1] : file_name
end

# Function to check if a package is outdated or conflicting
def get_conflicting_package_name(package_name)
  check_conflict_command = "sudo pacman -T #{package_name}"
  Open3.popen3(check_conflict_command) do |stdin, stdout, stderr, wait_thr|
    if wait_thr.value.success?
      stdout.read.strip
    else
      puts "Error: Failed to check for conflicting packages."
      ""
    end
  end
end

# Function to install packages from the SquashFS file
def install_packages_from_squashfs(mount_point)
  find_command = "find #{mount_point} -name \"*.pkg.tar.zst\""
  package_files = `#{find_command}`.split("\n")
  if package_files.empty?
    puts "No packages found in the SquashFS file."
    return false
  end

  # Extract base package names and deduplicate
  package_files = package_files.map { |file| [extract_base_package_name(file), file] }
  package_files.sort_by! { |name, _| name }
  unique_packages = package_files.reverse.uniq { |name, _| name }.reverse

  # First pass: Install all packages
  unique_packages.each do |_, pkg|
    install_command = "sudo pacman -U --noconfirm #{pkg}"
    print_colored("Installing package: #{pkg}\n", "\033[32m") # Green color
    result = system(install_command)
    if !result
      puts "Error: Failed to install package: #{pkg}"
    end
  end

  # Second pass: Check for conflicts and resolve them
  unique_packages.each do |_, pkg|
    package_name = extract_base_package_name(pkg)
    conflicting_package = get_conflicting_package_name(package_name)
    if !conflicting_package.empty?
      puts "Conflict detected with package: #{conflicting_package}"
      resolve_command = "sudo pacman -Sy --noconfirm #{package_name}"
      print_colored("Resolving conflict by installing: #{package_name}\n", "\033[32m") # Green color
      result = system(resolve_command)
      if !result
        puts "Error: Failed to resolve conflict for package: #{package_name}"
      end

      # Re-run installation from SquashFS
      reinstall_command = "sudo pacman -U --noconfirm #{pkg}"
      print_colored("Reinstalling package: #{pkg}\n", "\033[32m") # Green color
      result = system(reinstall_command)
      if !result
        puts "Error: Failed to reinstall package: #{pkg}"
      end
    end
  end

  true
end

# Function to read repository URLs from repos.txt
def read_repos_txt
  repos_file_path = "/tmp/Squashfs-Iso-Repos/repos.txt"
  unless File.exist?(repos_file_path)
    puts "Error: Failed to open repos.txt"
    return {}
  end

  repos = {}
  current_category = nil
  current_repo = nil

  File.foreach(repos_file_path) do |line|
    line.strip!
    next if line.empty?

    # Check if the line is a category (e.g., "Apex Squashfs Repos")
    if line.match?(/Repos/) && (line.match?(/Squashfs/) || line.match?(/Iso/))
      current_category = line
      current_repo = nil
    # Check if the line is a repository name (e.g., "Apex KdeLinux Stable Repos")
    elsif line.match?(/Repos/) && current_category
      current_repo = line
      repos[current_category] ||= {}
      repos[current_category][current_repo] ||= []
    # Check if the line is a link (e.g., "stable Package Database Build 21-02-2024 link 1")
    elsif line.match?(/https:\/\//) && current_category && current_repo
      repos[current_category][current_repo] << [line, ""]
    end
  end

  repos
end

# Main function
def main
  # Display ASCII art and title
  print_colored(<<~ASCII, "\033[33m")
    ░█████╗░██╗░░░░░░█████╗░██╗░░░██╗██████╗░███████╗███╗░░░███╗░█████╗░██████╗░░██████╗
    ██╔══██╗██║░░░░░██╔══██╗██║░░░██║██╔══██╗██╔════╝████╗░████║██╔══██╗██╔══██╗██╔════╝
    ██║░░╚═╝██║░░░░░███████║██║░░░██║██║░░██║█████╗░░██╔████╔██║██║░░██║██║░░██║╚█████╗░
    ██║░░██╗██║░░░░░██╔══██║██║░░░██║██║░░██║██╔══╝░░██║╚██╔╝██║██║░░██║██║░░██║░╚═══██╗
    ╚█████╔╝███████╗██║░░██║╚██████╔╝██████╔╝███████╗██║░╚═╝░██║╚█████╔╝██████╔╝██████╔╝
    ░╚════╝░╚══════╝╚═╝░░╚═╝░╚═════╝░╚═════╝░╚══════╝╚═╝░░░░░╚═╝░╚════╝░╚═════╝░╚═════╝░
  ASCII
  print_colored("\nclaudemods Arch Repo Utility v1.0 21-02-2025\n", "\033[33m")

  # Delete the Squashfs-Iso-Repos folder if it exists
  unless delete_squashfs_iso_repos_folder
    puts "Error: Failed to clean up existing repository folder. Exiting."
    return
  end

  # Download repos.txt first
  unless download_repos_txt
    puts "Error: Failed to download repos.txt. Exiting."
    return
  end

  # Read repository URLs from repos.txt
  repos = read_repos_txt
  if repos.empty?
    puts "Error: No repositories found in repos.txt. Exiting."
    return
  end

  # Main menu
  loop do
    puts "\nSelect a category:"
    categories = repos.keys
    categories.each_with_index do |category, index|
      print_colored("#{index + 1}. #{category}\n", "\033[33m")
    end
    print_colored("#{categories.size + 1}. Exit\n", "\033[33m")
    print "Enter your choice: "
    choice = gets.chomp.to_i

    if choice.between?(1, categories.size)
      selected_category = categories[choice - 1]
      puts "\nSelected category: #{selected_category}"

      # Display repositories in the selected category
      puts "\nSelect a repository:"
      repositories = repos[selected_category].keys
      repositories.each_with_index do |repo, index|
        print_colored("#{index + 1}. #{repo}\n", "\033[33m")
      end
      print_colored("#{repositories.size + 1}. Back to Main Menu\n", "\033[33m")
      print "Enter your choice: "
      repo_choice = gets.chomp.to_i

      if repo_choice.between?(1, repositories.size)
        selected_repo = repositories[repo_choice - 1]
        puts "\nSelected repository: #{selected_repo}"

        # Display links for the selected repository
        puts "\nAvailable links:"
        links = repos[selected_category][selected_repo]
        links.each_with_index do |link, index|
          print_colored("#{index + 1}. #{link[0]}\n", "\033[33m")
        end
        print_colored("#{links.size + 1}. Back to Category Menu\n", "\033[33m")
        print "Enter your choice: "
        link_choice = gets.chomp.to_i

        if link_choice.between?(1, links.size)
          selected_link = links[link_choice - 1][0]
          output_file_path = "/mnt/repo.squashfs"
          mount_point = "/mnt/repo"

          # Turn terminal green before executing commands
          print_colored("Executing commands...\n", "\033[32m")

          # Download the SquashFS file
          unless download_file_with_wget(selected_link, output_file_path)
            puts "Error: Failed to download repository SquashFS file."
            next
          end

          # Mount the SquashFS file
          unless mount_squashfs(output_file_path, mount_point)
            puts "Error: Failed to mount SquashFS file."
            next
          end

          # Install packages from the SquashFS file
          unless install_packages_from_squashfs(mount_point)
            puts "Error: Failed to install packages from SquashFS file."
          end

          # Unmount the SquashFS file
          unless unmount_squashfs(mount_point)
            puts "Error: Failed to unmount SquashFS file."
          end

          # Clean up mount point
          FileUtils.remove_dir(mount_point)
        elsif link_choice == links.size + 1
          next # Back to Category Menu
        else
          puts "Invalid choice. Returning to repository menu."
        end
      elsif repo_choice == repositories.size + 1
        next # Back to Main Menu
      else
        puts "Invalid choice. Returning to main menu."
      end
    elsif choice == categories.size + 1
      break # Exit the program
    else
      puts "Invalid choice. Please try again."
    end
  end
end

# Run the program
main
