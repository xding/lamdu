# Project Lamdu

[![Join the chat at https://gitter.im/lamdu/lamdu](https://badges.gitter.im/Join%20Chat.svg)](https://gitter.im/lamdu/lamdu?utm_source=badge&utm_medium=badge&utm_campaign=pr-badge&utm_content=badge)

This project aims to create a "next-generation", "live programming" environment
that radically improves the programming experience.

See the [Main Page](http://lamdu.org/)

## Installation

### [NodeJS](https://nodejs.org/en/) & Build Time

To drastically speed up Lamdu's installation under any OS, you can install
`nodejs >= 6.2.1`<sup>1</sup> beforehand, such that `node` is in your `$PATH`.

Enter `node -v` into terminal. If NodeJS is installed (and in your `$PATH`),
this will print your current version. If it isn't, you'll get an error.

If you do not install NodeJS, Lamdu's installation will build it from
source.

<sup>
**1. For Fedora Users:**
Fedora packages have very long names. This may lead to some confusion.
Consider `nodejs-1:6.11.2-1.fc25.x86_64`.
This example indicates a NodeJS version of `6.11`, plus a little.
The `-1:` is not a part of the version.
</sup>

#### osx

requires [brew](http://brew.sh/) and [git](https://git-scm.com/):

```shell
brew install leveldb haskell-stack
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install
~/.local/bin/lamdu

```

#### ubuntu

Optional: Install NodeJS from node's apt repository:

```shell
curl -sL https://deb.nodesource.com/setup_6.x | sudo -E bash -
sudo apt-get install -y nodejs
```

requires [stack](https://github.com/commercialhaskell/stack/releases)

```shell
sudo apt-get update -qq
sudo apt-get install git zlib1g-dev libglew-dev libleveldb-dev libglfw-dev -yq
sudo apt-get install libxrandr-dev libxi-dev libxcursor-dev libxinerama-dev -yq
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install
~/.local/bin/lamdu

```

#### fedora

Optional: Install NodeJS with `sudo dnf insall nodjs`.
Please see the starred note under "NodeJS & Build Time".

requires [stack](https://github.com/commercialhaskell/stack/releases)

```shell
sudo dnf install -y gcc gcc-c++ gmp-devel libXrandr-devel libXi-devel
sudo dnf install -y libXcursor-devel mesa-libGL-devel libGLU-devel
sudo dnf install -y libXinerama-devel leveldb-devel glew-devel
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install
~/.local/bin/lamdu
```

#### arch linux

requires [stack](https://github.com/commercialhaskell/stack/releases)

```shell
sudo pacman -S leveldb glfw libxrandr libxi libxcursor libxinerama
git clone --recursive https://github.com/lamdu/lamdu
cd lamdu
stack setup
stack install
~/.local/bin/lamdu

```

## Tutorial

*Note:* In the shortcut key combinations, "left" refers to the left cursor key.

### Simple expressions

At the top we have an interactive shell, where we can type calculations.

The `⋙` is our prompt to this shell. Think of it like a calculator:
you enter an expression, hit a button, and it tells you the answer.
The next time you use the calculator,
you clear whatever's in there and enter a new expression. Same here.

![Golden ratio example](https://i.imgur.com/vbPRcCO.png)

To type the calculation above:

* Type "**`1+s`**" at the prompt (`⋙`).
  Notice we have chosen "`1`" for the addition's left argument.
  However, we have only begun to type the second argument: it starts with an "s".
  Lamdu knows we have finalized the left argument because we have moved on from it,
  indicated by the `+`.
  But we have done nothing to indicate that just `s` is the second argument.
  To help us finalize the right argument, Lamdu has presented a menu of
  type-appropriate choices containing "s" in their names &ndash; "containing",
  not just "starting with". This menu updates as we type.
* Next, we will flesh out the "s" into a "sqrt".
  As of September 2017, "sqrt" should already be selected in the nearby menu,
  because it is alphabetically the first function in the library to contain an "s"
  in its name and to output a number.
  However your menu, take the path of fewest keystrokes:
  continuing to type the function's name
  reduces the menu options to just those that match.
  Cursor keys allow you to select from the menu.
  Hit **space** to chose your selected menu option.
* Type "**`5`**" and press **space**.
* Select the whole expression by pressing **shift+left** twice.
* Type "**`/2`**" and press **space**.
  Notice that Lamdu just automatically inserted the parentheses.

Lamdu displays the evaluation of each expression, whether the whole or a subexpression.
Such an automatic display is called an "annotation".
The annotation of an expression appears below that of any child expression.
For example, the evaluation of `(1 + sqrt 5) / 2`
appears below that of its child expression, `(1 + sqrt 5)`.
The former is `1.61...` and the latter is `3.23...`.

To keep the expression size from bloating, some annotations are shrunk,
like that of the `sqrt 5` above, which is `2.23...`.
To see this in normal size, navigate to the expression by going to the `sqrt`,
or to the `5`, and press **shift+left**.

We have just expressed the golden ratio.
To save it and give it a name, navigate to the `⋙` sign and press **return**.
Press Ctrl-X to extract the code into a new definition.
Notice the Ctrl-X took us away from the prompt and put us below it.
Type "**`golden`**" and **escape** to stop renaming.
You do not need to explicitly save - as Lamdu always saves the entire state.

### Creating a function

*Note:* Ctrl-Z is undo.

![Factorial function](https://i.imgur.com/9a5M5Jt.png)

To create the function above:

* Navigate to the "New..." button and press **space**.
* Lamdu spaces your code automatically.
  If you type a space after the first "x" below, Lamdu will think you want to specify a second argument to the function.

  The first equals sign after "fac" gets onto your screen without you typing it.
  However, after "fac x", you may type the equals sign anyways, or skip over it with the right cursor key.

Type "**`fac x=if x=0 1 x*f(x-1)`**"

We've now written the function. Let's use it.

* Go back up to the REPL, just right of the `⋙` symbol.
  Like with calculators, we want to clear anything in there before using it.
  If there is an expression there, press **shift+left** until all is selected, then hit **delete**.
* Type "**`fac 5`**" and press **space**.

Lamdu should now display the evaluation of the whole function, as well as its subexpresssions.
The active `if` branch (the `else`) is highlighted via a green background on the `|` symbol.
The `|` represents a [suspended computation](https://github.com/lamdu/lamdu/blob/master/doc/Language.md#suspended-computations).

This function is recursive and invoked additional applications of itself.
To navigate between these function applications,
navigate to the arrows under the `x` parameter and press **right** or **left**.

To rename any symbol, navigate to it, press **return** twice and edit the name.
Note that all references are displayed with the updated name correctly.

## Further Exploration / Help Documentation

In the lower-right of Lamdu's screen, you'll see that F1 brings up contextual help.

It shows all the key bindings currently active, which changes
according to the current context.
