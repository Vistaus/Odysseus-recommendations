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

    Compile this with valac --pkg webkit2gtk-4.0*/
WebKit.WebView construct_renderer() {
    var web = new WebKit.WebView();
    var win = new Gtk.OffscreenWindow();
    web.set_size_request(512, 512);
    web.zoom_level = 0.5;
    win.add(web);
    win.show_all();

    return web;
}
async string screenshot_link(WebKit.WebView web, string url) throws Error {
    var hook = web.load_changed.connect((evt) => {
        if (evt == WebKit.LoadEvent.FINISHED) screenshot_link.callback();
    });
    web.load_uri(url);
    yield;
    web.disconnect(hook);

    var shot = yield web.get_snapshot(WebKit.SnapshotRegion.VISIBLE,
            WebKit.SnapshotOptions.NONE, null);
    uint8[] png;
    Gdk.pixbuf_get_from_surface(shot, 0, 0, 512, 512).save_to_buffer(out png, "png");
    var encoded = Base64.encode(png);

    return encoded;
}

async void screenshot_locale(string path) throws Error {
    var file = new DataInputStream(yield File.new_for_path(path).read_async());
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
            stdout.printf("%f %s %i\n", 1.0/links.length, link,
                        (yield screenshot_link(renderer, link)).length);
        }
    }

    file.close();
}

static int main(string[] args) {
    Gtk.init(ref args);
    int ret = 0;
    var loop = new MainLoop();

    screenshot_locale.begin(args[1], (obj, res) => {
        try {
            screenshot_locale.end(res);
        } catch (Error err) {ret = -1;}
        loop.quit();
    });
    loop.run();
    return ret;
}