/**
* This file is part of Odysseus Web Browser's Recommendations site (Copyright Adrian Cochrane 2018).
*
* Odysseus is free software: you can redistribute it and/or modify
* it under the terms of the GNU General Public License as published by
* the Free Software Foundation, either version 3 of the License, or
* (at your option) any later version.
*
* Odysseus is distributed in the hope that it will be useful,
* but WITHOUT ANY WARRANTY; without even the implied warranty of
* MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
* GNU General Public License for more details.

* You should have received a copy of the GNU General Public License
* along with Odysseus.  If not, see <http://www.gnu.org/licenses/>.
*/
/** This script takes a screenshot of webpages to be used to represent their
    links both on Odysseus's Recommendations site and
    in Odysseus's topsites display.

    Compile this with valac --pkg webkit2gtk-4.0 */
errordomain DBError {CREATE, STATEMENT}
class Output {
    DataOutputStream file;
    public Output(File root, string lang) throws Error {
        var tsv_dir = root.get_child("tsv");
        if (!tsv_dir.query_exists()) tsv_dir.make_directory();
        var file = root.get_child("tsv").get_child(lang + ".tsv");
        this.file = new DataOutputStream(file.create(
                FileCreateFlags.REPLACE_DESTINATION | FileCreateFlags.PRIVATE));
    }

    public void write(double Pr, string uri, string screenshot) throws IOError {
        file.put_string("%f\t%s\t%s\n".printf(Pr, uri, screenshot));

        stdout.printf(".");
        stdout.flush();
    }
}

/* Render screenshots */
WebKit.WebView construct_renderer() {
    var web = new WebKit.WebView();
    var win = new Gtk.OffscreenWindow();
    web.set_size_request(512, 512);
    web.zoom_level = 0.5;
    win.add(web);
    win.show_all();

    return web;
}

errordomain ScreenshotError {FAILED, LOAD}
async string screenshot_link(WebKit.WebView web, string url) throws Error {
    var hook = web.load_changed.connect((evt) => {
        if (evt != WebKit.LoadEvent.FINISHED) return;

        screenshot_link.callback();
    });
    var errmsg = "";
    var errhook = web.load_failed.connect((evt, uri, err) => {
        errmsg = uri + ":\t" + err.message;
        screenshot_link.callback();
        return true; 
    });
    web.load_uri(url);
    yield;
    web.disconnect(hook);
    web.disconnect(errhook);
    web.stop_loading();
    if (errmsg != "") throw new ScreenshotError.LOAD(errmsg);

    var shot = yield web.get_snapshot(WebKit.SnapshotRegion.VISIBLE,
            WebKit.SnapshotOptions.NONE, null);
    if (shot == null) throw new ScreenshotError.FAILED("WebView.get_snapshot");

    var pixbuf = Gdk.pixbuf_get_from_surface(shot, 0, 0, 512, 512);
    var OUT_SIZE = 128;
    var thumbnail = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, OUT_SIZE, OUT_SIZE);
    pixbuf.scale(thumbnail, 0, 0, OUT_SIZE, OUT_SIZE,
                0, 0, 0.25, 0.25, Gdk.InterpType.NEAREST);
    var grayscale = new Gdk.Pixbuf(Gdk.Colorspace.RGB, true, 8, OUT_SIZE, OUT_SIZE);
    thumbnail.saturate_and_pixelate(grayscale, 0.0f, true);

    uint8[] png;
    grayscale.save_to_buffer(out png, "png");
    var encoded = Base64.encode(png);

    return encoded;
}

// Tries calling screenshot_link 3 times
async string try_screenshot_link(WebKit.WebView web, string url)
        throws Error {
    try {return yield screenshot_link(web, url);}
    catch (Error err) {
        try {return yield screenshot_link(web, url);}
        catch (Error err) {return yield screenshot_link(web, url);}
    }
}

/* Find links to screenshot */
async void screenshot_locale(Output output, File path) throws Error {
    var file = new DataInputStream(yield path.read_async());
    var renderer = construct_renderer();

    for (var line = yield file.read_line_async(); line != null;
            line = yield file.read_line_async()) {
        line = line.strip();
        if (line.length == 0 || line[0] == '#') continue;

        var links = line.split_set(" \t");
        // Throw out empty links
        var nonempty_links = new string[links.length];
        var nonempty_length = 0;
        for (var i = 0; i < links.length; i++) {
            if (links[i] == "") continue;
            nonempty_links[nonempty_length] = links[i];
            nonempty_length++;
        }
        links = nonempty_links[0:nonempty_length];

        foreach (var link in links) {
            try {
                output.write(1.0/links.length, link,
                        yield try_screenshot_link(renderer, link));
            } catch (Error err) {
                stderr.printf("Failed to screenshot page: %s\n", err.message);
            }
        }
    }

    file.close();
}

async void process_locales() throws Error {
    var repo = get_repo_root();
    var dir = get_repo_root().get_child("links");

    var files = dir.enumerate_children("standard::*", 0);
    for (var info = files.next_file(); info != null; info = files.next_file()) {
        if (info.get_name().has_suffix("~")) continue;
        try {
            var output = new Output(repo, info.get_name());
            yield screenshot_locale(output, dir.get_child(info.get_name()));
        } catch (Error err) {
            stderr.printf("syntax error in %s: %s\n", info.get_name(), err.message);
        }
    }
}

File get_repo_root() {
    var ret = File.new_for_path(".");
    while (!ret.get_child(".git").query_exists())
        ret = ret.get_parent();
    return ret;
}

/* Entry point */
static int main(string[] args) {
    Gtk.init(ref args);
    int ret = 0;
    var loop = new MainLoop();

    process_locales.begin((obj, res) => {
        try {
            process_locales.end(res);
        } catch (Error err) {ret = -1;}
        loop.quit();
    });
    loop.run();
    stdout.printf("\n");
    return ret;
}
