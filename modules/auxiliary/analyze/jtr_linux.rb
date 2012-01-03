##
# $Id$
##

##
# This file is part of the Metasploit Framework and may be subject to
# redistribution and commercial restrictions. Please see the Metasploit
# Framework web site for more information on licensing and terms of use.
# http://metasploit.com/framework/
#
##


require 'msf/core'

class Metasploit3 < Msf::Auxiliary

	include Msf::Auxiliary::JohnTheRipper

	def initialize
		super(
			'Name'            => 'John the Ripper Linux Password Cracker',
			'Version'         => '$Revision$',
			'Description'     => %Q{
					This module uses John the Ripper to identify weak passwords that have been
				acquired from unshadowed passwd files from Unix systems. The module will only crack
				MD5 and DES implementations by default. Set Crypt to true to also try to crack
				Blowfish and SHA implementations. Warning: This is much slower.
			},
			'Author'          =>
				[
					'TheLightCosine <thelightcosine[at]gmail.com>',
					'hdm'
				] ,
			'License'         => MSF_LICENSE  # JtR itself is GPLv2, but this wrapper is MSF (BSD)
		)

		register_options(
			[
				OptBool.new('Crypt',[false, 'Try crypt() format hashes(Very Slow)', false])
			]
		)

	end

	def run
		wordlist = Rex::Quickfile.new("jtrtmp")

		wordlist.write( build_seed().join("\n") + "\n" )
		wordlist.close

		hashlist = Rex::Quickfile.new("jtrtmp")

		myloots = myworkspace.loots.where('ltype=?', 'linux.hashes')
		unless myloots.nil? or myloots.empty?
			myloots.each do |myloot|
				begin
					usf = File.open(myloot.path, "rb")
				rescue Exception => e
					print_error("Unable to read #{myloot.path} \n #{e}")
				end
				usf.each_line do |row|
					row.gsub!(/\n/, ":#{myloot.host.address}\n")
					hashlist.write(row)
				end
			end
			hashlist.close

			print_status("HashList: #{hashlist.path}")

			print_status("Trying Format:md5 Wordlist: #{wordlist.path}")
			john_crack(hashlist.path, :wordlist => wordlist.path, :rules => 'single', :format => 'md5')
			print_status("Trying Format:md5 Rule: All4...")
			john_crack(hashlist.path, :incremental => "All4", :format => 'md5')
			print_status("Trying Format:md5 Rule: Digits5...")
			john_crack(hashlist.path, :incremental => "Digits5", :format => 'md5')


			print_status("Trying Format:des Wordlist: #{wordlist.path}")
			john_crack(hashlist.path, :wordlist => wordlist.path, :rules => 'single', :format => 'des')
			print_status("Trying Format:des Rule: All4...")
			john_crack(hashlist.path, :incremental => "All4", :format => 'des')
			print_status("Trying Format:des Rule: Digits5...")
			john_crack(hashlist.path, :incremental => "Digits5", :format => 'des')

			print_status("Trying Format:bsdi Wordlist: #{wordlist.path}")
			john_crack(hashlist.path, :wordlist => wordlist.path, :rules => 'single', :format => 'bsdi')
			print_status("Trying Format:bsdi Rule: All4...")
			john_crack(hashlist.path, :incremental => "All4", :format => 'bsdi')
			print_status("Trying Format:bsdi Rule: Digits5...")
			john_crack(hashlist.path, :incremental => "Digits5", :format => 'bsdi')

			if datastore['Crypt']
				print_status("Trying Format:crypt Wordlist: #{wordlist.path}")
				john_crack(hashlist.path, :wordlist => wordlist.path, :rules => 'single', :format => 'crypt')
				print_status("Trying Rule: All4...")
				john_crack(hashlist.path, :incremental => "All4", :format => 'crypt')
				print_status("Trying Rule: Digits5...")
				john_crack(hashlist.path, :incremental => "Digits5", :format => 'crypt')
			end


			cracked = john_show_passwords(hashlist.path)


			print_status("#{cracked[:cracked]} hashes were cracked!")

			cracked[:users].each_pair do |k,v|
				if v[0] == "NO PASSWORD"
					passwd=""
				else
					passwd=v[0]
				end
				print_good("Host: #{v.last}  User: #{k} Pass: #{passwd}")
				report_auth_info(
					:host  => v.last,
					:port => 22,
					:sname => 'ssh',
					:user => k,
					:pass => passwd
				)
			end
		end

	end

	def build_seed

		seed = []
		#Seed the wordlist with Database , Table, and Instance Names
		schemas = myworkspace.notes.where('ntype like ?', '%.schema%')
		unless schemas.nil? or schemas.empty?
			schemas.each do |anote|
				anote.data.each do |key,value|
					seed << key
					value.each{|a| seed << a}
				end
			end
		end

		instances = myworkspace.notes.where('ntype=?', 'mssql.instancename')
		unless instances.nil? or instances.empty?
			instances.each do |anote|
				seed << anote.data['InstanceName']
			end
		end

		# Seed the wordlist with usernames, passwords, and hostnames

		myworkspace.hosts.find(:all).each {|o| seed << john_expand_word( o.name ) if o.name }
		myworkspace.creds.each do |o|
			seed << john_expand_word( o.user ) if o.user
			seed << john_expand_word( o.pass ) if (o.pass and o.ptype !~ /hash/)
		end

		# Grab any known passwords out of the john.pot file
		john_cracked_passwords.values {|v| seed << v }

		#Grab the default John Wordlist
		john = File.open(john_wordlist_path, "rb")
		john.each_line{|line| seed << line.chomp}

		unless seed.empty?
			seed.flatten!
			seed.uniq!
		end

		print_status("Wordlist Seeded with #{seed.length} words")

		return seed

	end

end
