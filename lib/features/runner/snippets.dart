import 'package:flutter/material.dart';

import '../../constants/themes.dart';

/// Ready-made data science code for Python blocks: tap one and it's typed
/// in for you. Handy on a phone, where typing code is slow.
class Snippet {
  const Snippet(this.group, this.title, this.code);
  final String group;
  final String title;
  final String code;
}

const dataSnippets = <Snippet>[
  Snippet('Load', 'Read a CSV file', 'import pandas as pd\n\ndf = pd.read_csv("data.csv")\ndf.head()'),
  Snippet('Load', 'Read an Excel file', 'import pandas as pd\n\ndf = pd.read_excel("data.xlsx")\ndf.head()'),
  Snippet('Load', 'Make a small table', 'import pandas as pd\n\ndf = pd.DataFrame({\n    "city": ["Cairo", "Giza", "Alexandria"],\n    "orders": [40, 25, 31],\n})\ndf'),
  Snippet('Look', 'Size and column types', 'print(df.shape)\ndf.dtypes'),
  Snippet('Look', 'Summary of every column', 'df.describe(include="all").T'),
  Snippet('Look', 'Missing values per column', 'df.isna().sum().sort_values(ascending=False)'),
  Snippet('Look', 'Count each value', 'df["city"].value_counts()'),
  Snippet('Clean', 'Drop rows with missing values', 'df = df.dropna()\ndf.shape'),
  Snippet('Clean', 'Fill missing numbers with the median', 'df = df.fillna(df.median(numeric_only=True))'),
  Snippet('Clean', 'Remove duplicate rows', 'df = df.drop_duplicates()\ndf.shape'),
  Snippet('Clean', 'Text column to dates', 'df["date"] = pd.to_datetime(df["date"])'),
  Snippet('Shape', 'Filter rows', 'df[df["orders"] > 30]'),
  Snippet('Shape', 'Group and sum', 'df.groupby("city")["orders"].sum().sort_values(ascending=False)'),
  Snippet('Shape', 'Pivot table', 'df.pivot_table(index="city", columns="month", values="orders", aggfunc="sum")'),
  Snippet('Shape', 'Join two tables', 'merged = df.merge(other, on="id", how="left")\nmerged.head()'),
  Snippet('Chart', 'Histogram', 'import matplotlib.pyplot as plt\n\ndf["orders"].hist(bins=30)\nplt.title("orders")\nplt.show()'),
  Snippet('Chart', 'Bar chart of a group', 'import matplotlib.pyplot as plt\n\ndf.groupby("city")["orders"].sum().plot.bar()\nplt.show()'),
  Snippet('Chart', 'Line over time', 'import matplotlib.pyplot as plt\n\ndf.set_index("date")["orders"].plot()\nplt.show()'),
  Snippet('Chart', 'Scatter plot', 'import matplotlib.pyplot as plt\n\ndf.plot.scatter(x="price", y="orders")\nplt.show()'),
  Snippet('Chart', 'Correlation heatmap', 'import matplotlib.pyplot as plt\n\ncorr = df.select_dtypes("number").corr()\nplt.imshow(corr, cmap="coolwarm", vmin=-1, vmax=1)\nplt.xticks(range(len(corr)), corr.columns, rotation=45, ha="right")\nplt.yticks(range(len(corr)), corr.columns)\nplt.colorbar()\nplt.show()'),
  Snippet('Model', 'Train and test a model (scikit-learn)', 'from sklearn.model_selection import train_test_split\nfrom sklearn.ensemble import RandomForestRegressor\nfrom sklearn.metrics import mean_absolute_error\n\nX = df.select_dtypes("number").drop(columns=["orders"])\ny = df["orders"]\nX_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2, random_state=42)\n\nmodel = RandomForestRegressor(random_state=42).fit(X_train, y_train)\nprint("mean error:", mean_absolute_error(y_test, model.predict(X_test)))'),
  Snippet('Model', 'Linear regression', 'from sklearn.linear_model import LinearRegression\n\nX = df[["price"]]\ny = df["orders"]\nmodel = LinearRegression().fit(X, y)\nprint("slope:", model.coef_[0], "intercept:", model.intercept_)'),
  Snippet('Model', 'Group similar rows (k-means)', 'from sklearn.cluster import KMeans\n\nnumbers = df.select_dtypes("number").dropna()\ndf.loc[numbers.index, "group"] = KMeans(n_clusters=3, n_init="auto", random_state=42).fit_predict(numbers)\ndf["group"].value_counts()'),
  Snippet('Save', 'Save the table as CSV', 'df.to_csv("result.csv", index=False)\nprint("Saved result.csv: find it in Files")'),
];

/// Shows the snippets and returns the one picked.
Future<Snippet?> pickSnippet(BuildContext context) {
  return showModalBottomSheet<Snippet>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (c) {
      final color = Theme.of(c).colorScheme;
      final groups = <String>[];
      for (final s in dataSnippets) {
        if (!groups.contains(s.group)) groups.add(s.group);
      }
      return DraggableScrollableSheet(
        expand: false,
        initialChildSize: 0.75,
        builder: (c, scroll) => ListView(controller: scroll, padding: const EdgeInsets.fromLTRB(16, 0, 16, 24), children: [
          Text('Insert code', style: Theme.of(c).textTheme.titleLarge),
          const SizedBox(height: 4),
          Text('Change the file and column names (like "orders") to yours.',
              style: TextStyle(color: color.onSurfaceVariant)),
          for (final g in groups) ...[
            Padding(
              padding: const EdgeInsets.only(top: 16, bottom: 4),
              child: Text('// ${g.toLowerCase()}',
                  style: monoStyle(c, size: 12.5, weight: FontWeight.w700, color: color.primary)),
            ),
            for (final s in dataSnippets.where((s) => s.group == g))
              ListTile(
                contentPadding: EdgeInsets.zero,
                dense: true,
                title: Text(s.title),
                subtitle: Text(s.code.split('\n').firstWhere((l) => l.trim().isNotEmpty && !l.startsWith('import'),
                        orElse: () => s.code.split('\n').first),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: monoStyle(c, size: 11.5, color: color.onSurfaceVariant)),
                onTap: () => Navigator.pop(c, s),
              ),
          ],
        ]),
      );
    },
  );
}
