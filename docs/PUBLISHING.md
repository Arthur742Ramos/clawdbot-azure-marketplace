# Azure Marketplace Publishing Guide

## Prerequisites

### 1. Microsoft Partner Center Account
To publish to Azure Marketplace, you need:
- Microsoft Partner Center account: https://partner.microsoft.com/dashboard
- Enrolled in the Commercial Marketplace program
- Publisher profile created

### 2. Azure Subscription
- Subscription with the VM image in Azure Compute Gallery
- Current: Visual Studio Enterprise Subscription (ddb0b48c-aa74-4420-bf1b-49a3f7eaa970)

### 3. Image Requirements
- ✅ Generalized VM image in Azure Compute Gallery
- ✅ TrustedLaunch / Gen2 VM support
- ✅ Ubuntu 24.04 LTS base
- Gallery: `OpenclawGallery` in `CLAWDBOT-IMAGE-RG`
- Image Definition: `openclaw-vm-tl`
- Latest Version: `1.0.20260130`

## Publishing Steps

### Step 1: Create Partner Center Account (if needed)
1. Go to https://partner.microsoft.com/dashboard
2. Sign in with your Microsoft account
3. Enroll in Commercial Marketplace program
4. Complete publisher profile (company info, tax, banking)

### Step 2: Create a New Offer
1. In Partner Center → Marketplace offers → + New offer → Azure Virtual Machine
2. Offer ID: `openclaw-vm` (cannot change later)
3. Offer alias: `Openclaw AI Agent VM`

### Step 3: Offer Setup
- **Selling through Microsoft**: No (bring your own license / free)
- **Test drive**: Optional (can enable later)

### Step 4: Properties
- **Categories**: AI + Machine Learning, Developer Tools
- **Legal**: Standard Contract or custom EULA
- **Industries**: Optional

### Step 5: Offer Listing
Use content from `MARKETPLACE_LISTING.md`:
- Name, Summary, Description
- Search keywords
- Support/help links
- Screenshots (create 1280x720 or 1920x1080 images)
- Videos (optional)

### Step 6: Preview Audience
- Add Azure subscription IDs that can test before public launch
- Current subscription: `ddb0b48c-aa74-4420-bf1b-49a3f7eaa970`

### Step 7: Technical Configuration (Plan)
1. Create a Plan (e.g., "Ubuntu 24.04")
2. **Pricing model**: Free
3. **VM images**: 
   - Source: Azure Compute Gallery
   - Gallery: `/subscriptions/ddb0b48c-aa74-4420-bf1b-49a3f7eaa970/resourceGroups/CLAWDBOT-IMAGE-RG/providers/Microsoft.Compute/galleries/OpenclawGallery`
   - Image: `openclaw-vm-tl`
   - Version: `1.0.20260130`
4. **VM sizes**: Recommend B2s, B2ms; allow B1s-D4s range
5. **OS disk type**: StandardSSD_LRS or Premium_LRS
6. **Networking**: SSH (port 22)

### Step 8: Review and Publish
1. Review all sections
2. Click "Review and publish"
3. Wait for certification (1-3 business days)
4. Fix any certification issues if flagged
5. Once certified, go live!

## Post-Publishing

### Updating the Image
1. Create new VM, run setup.sh with updates
2. Prepare and capture new image version (e.g., 1.0.20260201)
3. Update plan in Partner Center with new version
4. Submit for re-certification

### Monitoring
- Partner Center Analytics for usage metrics
- Azure Monitor for VM health

## Resources
- [Azure VM Offer Creation Guide](https://learn.microsoft.com/en-us/azure/marketplace/azure-vm-offer-setup)
- [VM Image Requirements](https://learn.microsoft.com/en-us/azure/marketplace/azure-vm-image-test)
- [Partner Center Documentation](https://learn.microsoft.com/en-us/partner-center/)
