import 'package:flutter/material.dart';

/// Subscription management page with pricing plans and features
class SubscriptionPage extends StatefulWidget {
  static const String routeName = '/subscription';

  const SubscriptionPage({super.key});

  @override
  State<SubscriptionPage> createState() => _SubscriptionPageState();
}

class _SubscriptionPageState extends State<SubscriptionPage> {
  int _selectedPlanIndex = 0;
  bool _isAnnual = false;

  final List<SubscriptionPlan> _plans = [
    SubscriptionPlan(
      name: 'Free',
      monthlyPrice: 0,
      annualPrice: 0,
      features: [
        'Up to 100 patient records',
        '1 GB cloud storage',
        'Basic sync functionality',
        'Email support',
      ],
      limitations: [
        'Limited backup retention (7 days)',
        'No advanced analytics',
        'No priority support',
      ],
      isPopular: false,
      color: Colors.grey,
    ),
    SubscriptionPlan(
      name: 'Professional',
      monthlyPrice: 9.99,
      annualPrice: 99.99,
      features: [
        'Unlimited patient records',
        '50 GB cloud storage',
        'Advanced sync with conflict resolution',
        'Priority email support',
        'Advanced analytics dashboard',
        'Export to multiple formats',
        'Backup retention (90 days)',
      ],
      limitations: [],
      isPopular: true,
      color: Colors.blue,
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Subscription Plans'),
        centerTitle: true,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildHeader(),
            const SizedBox(height: 24),
            _buildBillingToggle(),
            const SizedBox(height: 24),
            _buildPlanCards(),
            const SizedBox(height: 32),
            _buildCurrentPlanStatus(),
          ],
        ),
      ),
      bottomNavigationBar: _buildBottomBar(),
    );
  }

  Widget _buildHeader() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'Choose Your Plan',
          style: Theme.of(context).textTheme.headlineMedium?.copyWith(
            fontWeight: FontWeight.bold,
          ),
        ),
        const SizedBox(height: 8),
        Text(
          'Upgrade to unlock advanced features and get more storage for your medical records.',
          style: Theme.of(context).textTheme.bodyLarge?.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
        ),
      ],
    );
  }

  Widget _buildBillingToggle() {
    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surfaceVariant.withOpacity(0.5),
        borderRadius: BorderRadius.circular(25),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          _buildToggleButton('Monthly', !_isAnnual),
          _buildToggleButton('Annual (Save 17%)', _isAnnual),
        ],
      ),
    );
  }

  Widget _buildToggleButton(String text, bool isSelected) {
    return GestureDetector(
      onTap: () {
        setState(() {
          _isAnnual = text.contains('Annual');
        });
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
        decoration: BoxDecoration(
          color: isSelected 
            ? Theme.of(context).colorScheme.primary
            : Colors.transparent,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Text(
          text,
          style: TextStyle(
            color: isSelected 
              ? Theme.of(context).colorScheme.onPrimary
              : Theme.of(context).colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.w600,
          ),
        ),
      ),
    );
  }

  Widget _buildPlanCards() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final isWide = constraints.maxWidth > 800;
        
        if (isWide) {
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: _plans.asMap().entries.map((entry) {
              return Expanded(
                child: Padding(
                  padding: EdgeInsets.only(
                    right: entry.key < _plans.length - 1 ? 16 : 0,
                  ),
                  child: _buildPlanCard(entry.value, entry.key),
                ),
              );
            }).toList(),
          );
        } else {
          return Column(
            children: _plans.asMap().entries.map((entry) {
              return Padding(
                padding: const EdgeInsets.only(bottom: 16),
                child: _buildPlanCard(entry.value, entry.key),
              );
            }).toList(),
          );
        }
      },
    );
  }

  Widget _buildPlanCard(SubscriptionPlan plan, int index) {
    final isSelected = _selectedPlanIndex == index;
    final price = _isAnnual ? plan.annualPrice : plan.monthlyPrice;
    final priceText = price == 0 ? 'Free' : '\$${price.toStringAsFixed(2)}';
    final periodText = price == 0 ? '' : _isAnnual ? '/year' : '/month';

    return GestureDetector(
      onTap: () {
        setState(() {
          _selectedPlanIndex = index;
        });
      },
      child: Container(
        padding: const EdgeInsets.all(20),
        decoration: BoxDecoration(
          color: isSelected 
            ? plan.color.withOpacity(0.1)
            : Theme.of(context).colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: isSelected 
              ? plan.color
              : Theme.of(context).colorScheme.outline.withOpacity(0.3),
            width: isSelected ? 2 : 1,
          ),
          boxShadow: isSelected ? [
            BoxShadow(
              color: plan.color.withOpacity(0.2),
              blurRadius: 8,
              offset: const Offset(0, 4),
            ),
          ] : null,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Plan header
            Row(
              children: [
                Expanded(
                  child: Text(
                    plan.name,
                    style: Theme.of(context).textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: isSelected ? plan.color : null,
                    ),
                  ),
                ),
                if (plan.isPopular)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                    decoration: BoxDecoration(
                      color: plan.color,
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text(
                      'POPULAR',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            
            // Price
            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Text(
                  priceText,
                  style: Theme.of(context).textTheme.headlineMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: isSelected ? plan.color : null,
                  ),
                ),
                if (periodText.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 4),
                    child: Text(
                      periodText,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
              ],
            ),
            
            if (_isAnnual && plan.monthlyPrice > 0) ...[
              const SizedBox(height: 4),
              Text(
                'Billed annually (\$${(plan.annualPrice / 12).toStringAsFixed(2)}/month)',
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
            ],
            
            const SizedBox(height: 20),
            
            // Features
            ...plan.features.map((feature) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.check_circle,
                    color: Colors.green,
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      feature,
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                  ),
                ],
              ),
            )),
            
            // Limitations
            ...plan.limitations.map((limitation) => Padding(
              padding: const EdgeInsets.only(bottom: 8),
              child: Row(
                children: [
                  Icon(
                    Icons.cancel,
                    color: Colors.red.withOpacity(0.7),
                    size: 16,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      limitation,
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ),
                ],
              ),
            )),
          ],
        ),
      ),
    );
  }

  Widget _buildCurrentPlanStatus() {
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Current Plan Status',
                  style: Theme.of(context).textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                  ),
                ),
                ElevatedButton.icon(
                  onPressed: () {
                    setState(() {
                      _selectedPlanIndex = 1; // Select Professional plan
                    });
                    // Scroll to bottom to show the subscribe button
                    Future.delayed(const Duration(milliseconds: 100), () {
                      Scrollable.ensureVisible(
                        context,
                        alignment: 1.0,
                        duration: const Duration(milliseconds: 300),
                      );
                    });
                  },
                  icon: const Icon(Icons.upgrade, size: 18),
                  label: const Text('Upgrade'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: Theme.of(context).colorScheme.primary,
                    foregroundColor: Theme.of(context).colorScheme.onPrimary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                Container(
                  width: 12,
                  height: 12,
                  decoration: const BoxDecoration(
                    color: Colors.green,
                    shape: BoxShape.circle,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  'Free Plan - Active',
                  style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                    fontWeight: FontWeight.w500,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Text(
              'You are currently using 45 of 100 patient records (45%)',
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                color: Theme.of(context).colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 8),
            LinearProgressIndicator(
              value: 0.45,
              backgroundColor: Theme.of(context).colorScheme.surfaceVariant,
              valueColor: AlwaysStoppedAnimation<Color>(
                Theme.of(context).colorScheme.primary,
              ),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.primaryContainer.withOpacity(0.3),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: Theme.of(context).colorScheme.primary.withOpacity(0.3),
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.info_outline,
                    color: Theme.of(context).colorScheme.primary,
                    size: 20,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Upgrade to Professional for unlimited records and advanced features',
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: Theme.of(context).colorScheme.primary,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }



  Widget _buildBottomBar() {
    final selectedPlan = _plans[_selectedPlanIndex];
    final isFreePlan = selectedPlan.monthlyPrice == 0;
    
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: Theme.of(context).colorScheme.shadow.withOpacity(0.1),
            blurRadius: 8,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    selectedPlan.name,
                    style: Theme.of(context).textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  if (!isFreePlan) ...[
                    const SizedBox(height: 4),
                    Text(
                      _isAnnual 
                        ? '\$${selectedPlan.annualPrice.toStringAsFixed(2)}/year'
                        : '\$${selectedPlan.monthlyPrice.toStringAsFixed(2)}/month',
                      style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(width: 16),
            ElevatedButton(
              onPressed: isFreePlan ? null : _handleSubscribe,
              style: ElevatedButton.styleFrom(
                backgroundColor: selectedPlan.color,
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
              ),
              child: Text(
                isFreePlan ? 'Current Plan' : 'Subscribe Now',
                style: const TextStyle(fontWeight: FontWeight.w600),
              ),
            ),
          ],
        ),
      ),
    );
  }

  void _handleSubscribe() {
    // TODO: Implement subscription logic
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Subscription functionality coming soon!'),
      ),
    );
  }
}

class SubscriptionPlan {
  final String name;
  final double monthlyPrice;
  final double annualPrice;
  final List<String> features;
  final List<String> limitations;
  final bool isPopular;
  final Color color;

  SubscriptionPlan({
    required this.name,
    required this.monthlyPrice,
    required this.annualPrice,
    required this.features,
    required this.limitations,
    required this.isPopular,
    required this.color,
  });
}