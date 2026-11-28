# Fixture sources

Each `.pbxproj` file in this folder is an unchanged copy of a real project file. Nobody edited a byte. The tests need real files, because a hand-written file cannot show how Xcode lays out text.

The test code makes every damaged variant from these files in memory. No damaged file is stored here.

Each file keeps the licence of its project. The MIT licence texts are written out below. The two Apache-2.0 projects have no NOTICE file. Their licence text is the same as the `LICENSE` file of their repository.

## old-format-mew.pbxproj

- Repository: https://github.com/mercari/Mew
- Path in the repository: `Mew.xcodeproj/project.pbxproj`
- Commit: `26b76134f111210a44412d78615e131cf6cf6938`
- Licence: MIT
- Copyright: Copyright (c) 2018 Mercari, Inc.
- Why it is here: An old project format (object version 46) with no shell script phase section. The editor must create that section.

## synchronized-fila.pbxproj

- Repository: https://github.com/owngoal-dev/Fila
- Path in the repository: `Fila.xcodeproj/project.pbxproj`
- Commit: `1f8f22e1e0d686370311b1d5d5dfd641f29c1106`
- Licence: MIT
- Copyright: Copyright (c) 2026 OwnGoal Studio
- Why it is here: A new project format (object version 77) with synchronized folders, hand-made object ids and configuration files. A bundle in a synchronized folder needs no file reference.

## folder-reference-twittertexteditor.pbxproj

- Repository: https://github.com/twitter/TwitterTextEditor
- Path in the repository: `Examples/Example.xcodeproj/project.pbxproj`
- Commit: `d326ac5e3b4511ab3fd2c98549a8c1dea8bce30a`
- Licence: Apache-2.0
- Copyright: The LICENSE file does not name a holder, because its template line is not filled in. The project file names the organization as Twitter, Inc.
- Why it is here: A folder file reference with the path `..`, and a Settings.bundle that is already a resource of the app target.

## settings-bundle-overland.pbxproj

- Repository: https://github.com/aaronpk/Overland-iOS
- Path in the repository: `Overland.xcodeproj/project.pbxproj`
- Commit: `924cfe256eee1974839fe1e1cfb5be006bcc9385`
- Licence: Apache-2.0
- Copyright: The LICENSE file does not name a holder, because its template line is not filled in. The project file names the organization as Aaron Parecki.
- Why it is here: A Settings.bundle that is already a resource, shell script phases from Pods, and a mix of YES and NO for the sandbox setting.

## multiple-targets-keyboardkit.pbxproj

- Repository: https://github.com/douglashill/KeyboardKit
- Path in the repository: `KeyboardKit.xcodeproj/project.pbxproj`
- Commit: `0aaf866ea702307158aa4b754cf3e518bbcf81da`
- Licence: MIT
- Copyright: Copyright 2019 Douglas Hill
- Why it is here: Several app targets in one project, a Settings.bundle that one of them copies, and the sandbox setting at YES.

## Licence texts

### mercari/Mew (MIT)

```
Copyright (c) 2018 Mercari, Inc.

MIT License

Permission is hereby granted, free of charge, to any person obtaining
a copy of this software and associated documentation files (the
"Software"), to deal in the Software without restriction, including
without limitation the rights to use, copy, modify, merge, publish,
distribute, sublicense, and/or sell copies of the Software, and to
permit persons to whom the Software is furnished to do so, subject to
the following conditions:

The above copyright notice and this permission notice shall be
included in all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### owngoal-dev/Fila (MIT)

```
MIT License

Copyright (c) 2026 OwnGoal Studio

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
SOFTWARE.
```

### douglashill/KeyboardKit (MIT)

```
The MIT License (MIT)

Copyright 2019 Douglas Hill

Permission is hereby granted, free of charge, to any person obtaining a copy of
this software and associated documentation files (the "Software"), to deal in
the Software without restriction, including without limitation the rights to
use, copy, modify, merge, publish, distribute, sublicense, and/or sell copies of
the Software, and to permit persons to whom the Software is furnished to do so,
subject to the following conditions:

The above copyright notice and this permission notice shall be included in all
copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY, FITNESS
FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR
COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER
IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN
CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.
```

### twitter/TwitterTextEditor and aaronpk/Overland-iOS (Apache-2.0)

The licence text is the same as the `LICENSE` file of each repository. Neither repository has a NOTICE file.
