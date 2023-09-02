{ pkgs ? import <nixpkgs> {}
}:

pkgs.callPackage (
  { runCommand
  , ruby
  }:
  let
    configuredRuby = (ruby.withPackages (pkgs: with pkgs; [
      jwt
    ]));
  in
  runCommand "www-preview" {
    src = ./.;
    nativeBuildInputs = [
      configuredRuby
    ];
  } ''
    mkdir -vp $out/bin
    cp -rv $src $out/libexec
    cat > $out/bin/doit.rb <<EOF
    #!${configuredRuby}/bin/ruby
    load "$out/libexec/doit.rb"
    EOF
    chmod +x $out/bin/doit.rb
  ''
) {}
