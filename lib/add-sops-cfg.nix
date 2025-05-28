{
  pkgs
}:
pkgs.writers.writePython3Bin "add-sops-cfg"
  {
    libraries = [
      pkgs.python312Packages.ruamel-yaml
    ];
  }
  ''
    import argparse
    from ruamel.yaml import YAML
    from ruamel.yaml.scalarstring import PlainScalarString


    class Yaml:
        def __init__(self, path):
            self.__y = YAML()
            self.__y.preserve_quotes = True

            self.path = path

        def read(self):
            content = {}
            try:
                with open(self.path, 'r') as f:
                    content = self.__y.load(f)
            except FileNotFoundError:
                pass
            return content

        def write(self, content):
            with open(self.path, 'w') as f:
                self.__y.dump(content, f)


    def find_anchor_for_alias(yaml_data, alias):
        for i, item in enumerate(yaml_data):
            if item.anchor.value == alias:
                return i
        return None


    def find_creation_rule(yaml_data, path_regex):
        for item in yaml_data:
            if 'path_regex' in item \
                    and item['path_regex'] == path_regex:
                return item
        return None


    def unique(lst):
        return sorted(list(set(lst)))


    def add_alias(args):
        yaml = Yaml(args.sops_cfg)

        content = yaml.read()

        anchor_to_add = PlainScalarString(args.sops_key, anchor=args.alias)
        if 'keys' not in content:
            content["keys"] = [anchor_to_add]
        else:
            anchor_index = find_anchor_for_alias(content['keys'], args.alias)
            if anchor_index is None:
                content["keys"] += [anchor_to_add]
            else:
                content["keys"][anchor_index] = anchor_to_add
                for rule in content.get('creation_rules', []):
                    for key_group in rule.get('key_groups', []):
                        for i, key in enumerate(key_group.get('age', [])):
                            if key.anchor.value == args.alias:
                                key_group['age'][i] = anchor_to_add

        content["keys"] = sorted(content["keys"])

        yaml.write(content)


    def add_parser_path_regex(args):
        yaml = Yaml(args.sops_cfg)

        content = yaml.read()

        anchor_index = find_anchor_for_alias(content['keys'], args.alias)
        if anchor_index is None:
            raise Exception('Cannot add alias to not existing anchor')

        if 'creation_rules' not in content:
            content["creation_rules"] = [{
              "path_regex": args.path_regex,
              "key_groups": [
                {
                  "age": [
                    content["keys"][anchor_index]
                  ]
                }
              ]
            }]
        else:
            existing_creation_rule \
                = find_creation_rule(content['creation_rules'], args.path_regex)
            if existing_creation_rule is None:
                content["creation_rules"] += [{
                  "path_regex": args.path_regex,
                  "key_groups": [
                    {
                      "age": [
                        content["keys"][anchor_index]
                      ]
                    }
                  ]
                }]
            else:
                existing_creation_rule["key_groups"][0]["age"] \
                    += [content["keys"][anchor_index]]
                existing_creation_rule["key_groups"][0]["age"] \
                    = unique(existing_creation_rule["key_groups"][0]["age"])

        yaml.write(content)


    def main():
        parser = argparse.ArgumentParser(
            prog='Add keys to Sops config')
        parser.add_argument('-o', '--sops-cfg')

        cmdparsers = parser.add_subparsers()

        parser_path_regex = cmdparsers.add_parser('path-regex')
        parser_path_regex.add_argument('alias')
        parser_path_regex.add_argument('path_regex', metavar='path-regex')
        parser_path_regex.set_defaults(func=add_parser_path_regex)

        alias = cmdparsers.add_parser('alias')
        alias.add_argument('alias')
        alias.add_argument('sops_key', metavar='sops-key')
        alias.set_defaults(func=add_alias)

        args = parser.parse_args()
        args.func(args)


    if __name__ == "__main__":
        main()
  ''
