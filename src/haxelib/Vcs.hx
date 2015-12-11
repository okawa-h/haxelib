/*
 * Copyright (C)2005-2015 Haxe Foundation
 *
 * Permission is hereby granted, free of charge, to any person obtaining a
 * copy of this software and associated documentation files (the "Software"),
 * to deal in the Software without restriction, including without limitation
 * the rights to use, copy, modify, merge, publish, distribute, sublicense,
 * and/or sell copies of the Software, and to permit persons to whom the
 * Software is furnished to do so, subject to the following conditions:
 *
 * The above copyright notice and this permission notice shall be included in
 * all copies or substantial portions of the Software.
 *
 * THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
 * IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
 * FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
 * AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
 * LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING
 * FROM, OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER
 * DEALINGS IN THE SOFTWARE.
 */
package haxelib;

import sys.FileSystem;

interface IVcs
{
	public var name(default, null):String;
	public var directory(default, null):String;
	public var executable(default, null):String;
	//TODO: public var internalDirectory(default, null):String;

	public var available(get_available, null):Bool;



	/**
		Clone repo into CWD.
		CWD must be like "...haxelib-repo/lib/git" for Git.
	**/
	public function clone(libPath:String, vcsPath:String, ?branch:String, ?version:String, ?settings:Settings):Void;

	// check available updates for repo in CWD/{directory}
	//TODO: public function updatable(libName:String):Void;

	/**
		Update to HEAD repo contains in CWD or CWD/`Vcs.directory`.
		CWD must be like "...haxelib-repo/lib/git" for Git.
		Returns `true` if update successful.
	**/
	public function update(libName:String, ?settings:Settings):Bool;

	// reset all changes in repo in CWD/{directory}
	//TODO: public function reset(?cwd:String):Void;
}


@:enum abstract VcsID(String) to String
{
	var Hg = "hg";
	var Git = "git";
}

enum VcsError
{
	VcsUnavailable(vcs:Vcs);
	CantCloneRepo(vcs:Vcs, repo:String, ?stderr:String);
	CantCheckoutBranch(vcs:Vcs, branch:String, stderr:String);
	CantCheckoutVersion(vcs:Vcs, version:String, stderr:String);
}


typedef Settings =
{
	var flat:Bool;
	@:optional var quiet:Bool;
	@:optional var debug:Bool;
};


class Vcs implements IVcs
{
	private static var reg:Map<VcsID, Vcs>;

	//----------- properties, fields ------------//

	public var name(default, null):String;
	public var directory(default, null):String;
	public var executable(default, null):String;

	public var available(get_available, null):Bool;
	private var availabilityChecked:Bool = false;
	private var executableSearched:Bool = false;

	//--------------- constructor ---------------//

	public static function initialize()
	{
		if(reg == null)
			reg = [VcsID.Git => new Git(), VcsID.Hg => new Mercurial()];
		else
		{
			if(reg.get(VcsID.Git) == null)
				reg.set(VcsID.Git, new Git());
			if(reg.get(VcsID.Hg) == null)
				reg.set(VcsID.Hg, new Mercurial());
		}
	}


	private function new(executable:String, directory:String, name:String)
	{
		this.name = name;
		this.directory = directory;
		this.executable = executable;
	}


	//----------------- static ------------------//

	public static function get(id:VcsID):Null<Vcs>
	{
		initialize();
		return reg.get(id);
	}

	private static function set(id:VcsID, vcs:Vcs, ?rewrite:Bool):Void
	{
		initialize();
		var existing = reg.get(id) != null;
		if(!existing || (existing && rewrite))
			reg.set(id, vcs);
	}

	public static function getVcsForDevLib(libPath:String):Null<Vcs>
	{
		initialize();
		for(k in reg.keys())
		{
			if(FileSystem.exists(libPath + "/" + k) && FileSystem.isDirectory(libPath + "/" + k))
				return reg.get(k);
		}
		return null;
	}

    static function command(cmd:String, args:Array<String>) {
        var p = new sys.io.Process(cmd, args);
        var code = p.exitCode();
        return {
            code: code,
            out: (code == 0 ? p.stdout.readAll().toString() : p.stderr.readAll().toString())
        };
    }

	//--------------- initialize ----------------//

	private function searchExecutable():Void
	{
		executableSearched = true;
	}

	private function checkExecutable():Bool
	{
		available =
		executable != null && try
		{
			Vcs.command(executable, []).code == 0;
		}
		catch(e:Dynamic) false;
		availabilityChecked = true;

		if(!available && !executableSearched)
			searchExecutable();

		return available;
	}

	@:final function get_available():Bool
	{
		if(!availabilityChecked)
			checkExecutable();
		return this.available;
	}

	//----------------- ctrl -------------------//

	public function clone(libPath:String, vcsPath:String, ?branch:String, ?version:String, ?settings:Settings):Void
	{
		throw "This method must be overriden.";
	}

	public function update(libName:String, ?settings:Settings):Bool
	{
		throw "This method must be overriden.";
		return false;
	}


	public function toString():String
	{
		return Type.getClassName(Type.getClass(this));
	}
}


class Git extends Vcs
{
	public static function init()
	{
		Vcs.set(VcsID.Git, new Git());
	}

	public function new()
		super("git", "git", "Git");


	override private function checkExecutable():Bool
	{
		available =
		executable != null && try
		{
			// with `help` cmd because without any cmd `git` can return exit-code = 1.
			Vcs.command(executable, ["help"]).code == 0;
		}
		catch(e:Dynamic) false;
		availabilityChecked = true;

		if(!available && !executableSearched)
			searchExecutable();

		return available;
	}

	override private function searchExecutable():Void
	{
		super.searchExecutable();

		if(available)
			return;

		// if we have already msys git/cmd in our PATH
		var match = ~/(.*)git([\\|\/])cmd$/;
		for(path in Sys.getEnv("PATH").split(";"))
		{
			if(match.match(path.toLowerCase()))
			{
				var newPath = match.matched(1) + executable + match.matched(2) + "bin";
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + newPath);
			}
		}
		if(checkExecutable())
			return;
		// look at a few default paths
		for(path in ["C:\\Program Files (x86)\\Git\\bin", "C:\\Progra~1\\Git\\bin"])
			if(FileSystem.exists(path))
			{
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + path);
				if(checkExecutable())
					return;
			}
	}

	override public function update(libName:String, ?settings:Settings):Bool
	{
		var doPull = true;

		if(0 != Sys.command(executable, ["diff", "--exit-code"]) || 0 != Sys.command(executable, ["diff", "--cached", "--exit-code"]))
		{
			if (Cli.ask("Reset changes to " + libName + " " + name + " repo so we can pull latest version?")) {
				Sys.command(executable, ["reset", "--hard"]);
			} else {
				doPull = false;
				Sys.println(name + " repo left untouched");
			}
		}
		if(doPull)
		{
			var code = Sys.command(executable, ["pull"]);
			// But if before we pulled specified branch/tag/rev => then possibly currently we haxe "HEAD detached at ..".
			if(code != 0)
			{
				// get parent-branch:
				var branch = Vcs.command(executable, ["show-branch"]).out;
				var regx = ~/\[([^]]*)\]/;
				if(regx.match(branch))
					branch = regx.matched(1);

				Sys.command(executable, ["checkout", branch, "--force"]);
				Sys.command(executable, ["pull"]);
			}
		}
		return doPull;
	}

	override public function clone(libPath:String, url:String, ?branch:String, ?version:String, ?settings:Settings):Void
	{
		var vcsArgs = ["clone", url, libPath];

		if(settings == null || !settings.flat)
			vcsArgs.push('--recursive');

		//TODO: move to Vcs.run(vcsArgs)
		//TODO: use settings.quiet
		if(Sys.command(executable, vcsArgs) != 0)
		{
			throw VcsError.CantCloneRepo(this, url/*, ret.out*/);
		}


		var cwd = Cli.cwd;
		Cli.cwd = libPath;

		if(branch != null)
		{
			var ret = Vcs.command(executable, ["checkout", branch]);
			if(ret.code != 0)
				throw VcsError.CantCheckoutBranch(this, branch, ret.out);
		}

		if(version != null)
		{
			var ret = Vcs.command(executable, ["checkout", "tags/" + version]);
			if(ret.code != 0)
				throw VcsError.CantCheckoutVersion(this, version, ret.out);
		}

		// return prev. cwd:
		Cli.cwd = cwd;
	}
}


class Mercurial extends Vcs
{
	public static function init()
	{
		Vcs.set(VcsID.Hg, new Mercurial());
	}

	public function new()
		super("hg", "hg", "Mercurial");

	override private function searchExecutable():Void
	{
		super.searchExecutable();

		if(available)
			return;

		// if we have already msys git/cmd in our PATH
		var match = ~/(.*)hg([\\|\/])cmd$/;
		for(path in Sys.getEnv("PATH").split(";"))
		{
			if(match.match(path.toLowerCase()))
			{
				var newPath = match.matched(1) + executable + match.matched(2) + "bin";
				Sys.putEnv("PATH", Sys.getEnv("PATH") + ";" + newPath);
			}
		}
		checkExecutable();
	}

	override public function update(libName:String, ?settings:Settings):Bool
	{
		var changed = false;
		Vcs.command(executable, ["pull"]);
		var summary = Vcs.command(executable, ["summary"]).out;
		var diff = Vcs.command(executable, ["diff", "-U", "2", "--git", "--subrepos"]);
		var status = Vcs.command(executable, ["status"]);

		// get new pulled changesets:
		// (and search num of sets)
		summary = summary.substr(0, summary.length - 1);
		summary = summary.substr(summary.lastIndexOf("\n") + 1);
		// we don't know any about locale then taking only Digit-exising:s
		changed = ~/(\d)/.match(summary);
		if(changed)
			// print new pulled changesets:
			Sys.println(summary);


		if(diff.code + status.code + diff.out.length + status.out.length != 0)
		{
			Sys.println(diff.out);
			if (Cli.ask("Reset changes to " + libName + " " + name + " repo so we can update to latest version?")) {
				Sys.command(executable, ["update", "--clean"]);
			} else {
				changed = false;
				Sys.println(name + " repo left untouched");
			}
		}
		else if(changed)
			Sys.command(executable, ["update"]);

		return changed;
	}

	override public function clone(libPath:String, url:String, ?branch:String, ?version:String, ?settings:Settings):Void
	{
		var vcsArgs = ["clone", url, libPath];

		if(branch != null)
		{
			vcsArgs.push("--branch");
			vcsArgs.push(branch);
		}

		if(version != null)
		{
			vcsArgs.push("--rev");
			vcsArgs.push(version);
		}

		if(Sys.command(executable, vcsArgs) != 0)
			throw VcsError.CantCloneRepo(this, url/*, ret.out*/);
	}
}